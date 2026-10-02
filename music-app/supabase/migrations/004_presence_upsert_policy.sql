-- PostgREST upsert needs to inspect the caller's existing presence row during
-- ON CONFLICT handling. This owner-only SELECT policy keeps the row private
-- while allowing authenticated web/mobile heartbeats to update it.
-- Safe to run more than once, after 002_admin_presence.sql.

drop policy if exists "presence_select_own" on public.user_presence;
create policy "presence_select_own" on public.user_presence for select to authenticated
using ((select auth.uid()) = user_id);

grant select, insert, update on public.user_presence to authenticated;
