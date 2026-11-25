-- B6: chat without a match (POST /api/v1/conversation; decision in
-- docs/decisions/frontend-f4-chat.md item 4, user 2026-11-25).
--
-- A general rules question has no match, so its metadata row has no match_context_id (and no
-- assessment_id). Still metadata only (DEC-14): no session id, question, answer or IP. These
-- rows are deleted after 30 days by purge_old_conversation_data like every other chat row.

alter table public.conversation_events alter column match_context_id drop not null;
comment on column public.conversation_events.match_context_id is
  'The match the question was about; null for a general question asked without a match.';
