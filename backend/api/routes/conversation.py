"""POST /match-contexts/{id}/conversation (B5; FR-AGT-001..006, P-06, P-20, DEC-14).

One question, one answer. The answer explains the current deterministic assessment and approved
documents; it never classifies. Order (B5 plan section 2):

    token (401) -> match (404) -> limit step (429 / not counted) -> topic check ->
    current assessment -> retrieval -> prompt -> providers with the answer check -> response
    -> one metadata row in conversation_events.

When no answer can be shown, ``generation`` is "unavailable", ``answer`` is null and a limitation
says why; the app still shows the assessment. ``AGENT_NOT_AUTHORITY`` is always present.
"""

import logging
import time
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from api.deps import (
    get_adapter_groups,
    get_ai_generators,
    get_connect,
    get_embedder,
    get_lightning_fetcher,
    get_settings_dep,
    require_session,
)
from api.errors import ApiError, rate_limited
from api.routes.match_contexts import load_match
from api.schemas.common import (
    ERROR_RESPONSES,
    INVALID_SESSION_RESPONSE,
    NOT_FOUND_RESPONSE,
    ErrorCode,
    Limitation,
)
from api.schemas.conversation import (
    ConversationLimitationCode as Code,
)
from api.schemas.conversation import (
    ConversationRequest,
    ConversationResponse,
)
from services.ai_providers.base import ProviderError
from services.ai_providers.provider_router.router import ProviderRouter
from services.chat_sessions.limiter import ChatLimiter, Counted, NotCounted, RateLimited
from services.conversation.guard import GuardResult, check_answer
from services.conversation.prompts import build_prompt
from services.conversation.topic import OFF_TOPIC_MESSAGE, is_on_topic
from services.rag.context_builder.builder import build_context
from services.rag.retrieval.hybrid import HybridRetriever
from services.safety_engine.assessment_service import current_assessment
from services.safety_engine.rules import get_rules
from shared.db.conversation_events import ConversationEvent, PgConversationEventRepository
from shared.db.pool import ConnectionFactory
from shared.settings import Settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/match-contexts", tags=["conversation"], responses=ERROR_RESPONSES)

MESSAGES: dict[Code, str] = {
    Code.AGENT_NOT_AUTHORITY: "AI-generated explanation of the assessment. Officials make the "
    "decision.",
    Code.AI_UNAVAILABLE: "The AI explanation is unavailable right now. The safety assessment "
    "still applies.",
    Code.DAILY_LIMIT_REACHED: "Pitchy's AI questions for today are used up. The safety "
    "assessment still applies.",
    Code.ANSWER_CHECK_FAILED: "No AI answer passed Pitchy's safety check, so none is shown. The "
    "safety assessment still applies.",
    Code.RETRIEVAL_KEYWORD_ONLY: "The document search used keywords only, so fewer guidance "
    "passages may have been found.",
    Code.OFF_TOPIC: OFF_TOPIC_MESSAGE,
}


def _limit(code: Code) -> Limitation:
    return Limitation(code=code.value, message=MESSAGES[code])


@router.post(
    "/{match_context_id}/conversation",
    response_model=ConversationResponse,
    responses={**NOT_FOUND_RESPONSE, **INVALID_SESSION_RESPONSE},
)
def ask_question(
    match_context_id: UUID,
    body: ConversationRequest,
    session_key: Annotated[bytes, Depends(require_session)],
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
    settings: Annotated[Settings, Depends(get_settings_dep)],
    groups: Annotated[list, Depends(get_adapter_groups)],
    generators: Annotated[list, Depends(get_ai_generators)],
    fetch_lightning=Depends(get_lightning_fetcher),  # noqa: B008
    embedder=Depends(get_embedder),  # noqa: B008
) -> ConversationResponse:
    """Role-adapted explanation of the current assessment and approved guidance (one question).

    Limited per session (10 per 10 minutes, then a 20-minute cooldown: 429 with ``retry_at``).
    Off-topic questions get a fixed decline (limitation OFF_TOPIC) and no AI answer.
    """
    started = time.monotonic()
    load_match(connect, match_context_id)  # 404 before anything is counted
    configured = any(g.configured for g in generators)
    limiter = ChatLimiter(connect, settings)
    decision = limiter.check_and_count(session_key, providers_configured=configured)
    if isinstance(decision, RateLimited):
        raise rate_limited(decision.retry_at)
    if not isinstance(decision, Counted | NotCounted):  # SessionUnknown: purged since the check
        raise ApiError(401, ErrorCode.INVALID_SESSION, "Missing or invalid session token.")

    def finish(
        outcome: Code | None,
        limitations,
        *,
        assessment=None,
        answer=None,
        references=(),
        provider=None,
        provider_called=False,
        retrieval_mode=None,
    ):
        generated = answer is not None
        refs = list(references)
        _record(connect, ConversationEvent(
            match_context_id=match_context_id,
            assessment_id=assessment.id if assessment else None,
            role=body.role.value,
            generation="generated" if generated else "unavailable",
            outcome_code="GENERATED" if generated else outcome.value,
            provider_called=provider_called,
            provider=provider if generated else None,
            reference_keys=sorted({r.document_id for r in refs}),
            retrieval_mode=retrieval_mode,
            duration_ms=int((time.monotonic() - started) * 1000),
        ))  # fmt: skip
        if isinstance(decision, Counted) and not provider_called:
            # Off-topic, or the router called nobody: the daily AI slot goes back. A request
            # that fails before this point keeps its slot (the cap is then reached early, never
            # exceeded).
            limiter.release(decision)
        own = [_limit(Code.AGENT_NOT_AUTHORITY)] + ([_limit(outcome)] if outcome else [])
        return ConversationResponse(
            match_context_id=match_context_id,
            assessment_id=assessment.id if assessment else None,
            role=body.role,
            generation="generated" if generated else "unavailable",
            answer=answer,
            references=refs,
            limitations=own + list(limitations),
            responded_at=datetime.now(UTC),
        )  # fmt: skip

    def assess():
        return current_assessment(connect, settings, groups, fetch_lightning, match_context_id)

    if isinstance(decision, NotCounted):
        assessment = assess()
        return finish(Code(decision.reason), assessment.limitations, assessment=assessment)
    if not is_on_topic(body.question):
        return finish(Code.OFF_TOPIC, [])

    assessment = assess()
    extra: list[Limitation] = []
    query_vector = None
    if embedder is not None:
        try:
            query_vector = embedder.embed([body.question], task="query")[0]
        except ProviderError as exc:
            logger.info("Question embedding failed: %s", exc.code)
    if query_vector is None:
        extra.append(_limit(Code.RETRIEVAL_KEYWORD_ONLY))
    retrieval = HybridRetriever(connect).search(body.question, query_vector)
    context = build_context(assessment, retrieval)
    system, prompt = build_prompt(context, body.role, body.question)

    rules = get_rules()
    checked: dict[str, GuardResult] = {}

    def accept(generation) -> bool:
        result = check_answer(generation.text, context, rules)
        checked["last"] = result
        if not result.ok:
            logger.info("Answer from %s rejected: %s", generation.provider, result.reason)
        return result.ok

    routed = ProviderRouter(generators).run(system, prompt, accept)
    common = dict(
        assessment=assessment, provider_called=routed.provider_called,
        retrieval_mode=retrieval.mode,
    )  # fmt: skip
    limitations = extra + list(assessment.limitations)
    if routed.generation is not None:
        result = checked["last"]
        if result.reason == "OFF_TOPIC":
            return finish(Code.OFF_TOPIC, [], **common)
        return finish(
            None, limitations, answer=result.answer,
            references=context.references_for(result.cited),
            provider=routed.generation.provider, **common,
        )  # fmt: skip
    rejected = any(code == "ANSWER_REJECTED" for _, code in routed.attempts)
    outcome = Code.ANSWER_CHECK_FAILED if rejected else Code.AI_UNAVAILABLE
    return finish(outcome, limitations, **common)


def _record(connect: ConnectionFactory, event: ConversationEvent) -> None:
    """Audit row (DEC-14). A failure is logged and never loses the user's answer."""
    try:
        PgConversationEventRepository(connect).record(event)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Could not record conversation event: %s", type(exc).__name__)
