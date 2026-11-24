"""Tries the text providers in a fixed order within a total time budget (DEC-10)."""

import logging
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field

from services.ai_providers.base import Generation, ProviderError, ProviderName, TextGenerator

logger = logging.getLogger(__name__)


@dataclass
class RouterResult:
    generation: Generation | None
    attempts: list[tuple[ProviderName, str]] = field(default_factory=list)
    provider_called: bool = False


class ProviderRouter:
    def __init__(
        self,
        generators: Sequence[TextGenerator],
        *,
        per_call_timeout_s: float = 15.0,
        total_timeout_s: float = 40.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._generators = list(generators)
        self._per_call = per_call_timeout_s
        self._total = total_timeout_s
        self._clock = clock

    def run(self, system: str, prompt: str, accept: Callable[[Generation], bool]) -> RouterResult:
        result = RouterResult(generation=None)
        start = self._clock()
        for generator in self._generators:
            if not generator.configured:
                result.attempts.append((generator.name, "NOT_CONFIGURED"))
                continue
            remaining = self._total - (self._clock() - start)
            if remaining <= 0:
                result.attempts.append((generator.name, "BUDGET_EXHAUSTED"))
                continue
            result.provider_called = True
            try:
                generation = generator.generate(
                    system, prompt, timeout_s=min(self._per_call, remaining)
                )
            except ProviderError as exc:
                result.attempts.append((generator.name, exc.code))
                continue
            except Exception:  # noqa: BLE001 - a broken adapter must not stop the fallback chain
                result.attempts.append((generator.name, "ERROR"))
                continue
            if accept(generation):
                result.attempts.append((generator.name, "OK"))
                result.generation = generation
                break
            result.attempts.append((generator.name, "ANSWER_REJECTED"))
        logger.info("AI provider attempts: %s", result.attempts)
        return result
