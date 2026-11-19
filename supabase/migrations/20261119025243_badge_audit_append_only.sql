-- Supabase default privileges grant service_role more than an append-only audit
-- requires. Decisions insert history; no application route may rewrite it.
revoke update, delete, truncate, references, trigger on public.app_badge_audit from service_role;
