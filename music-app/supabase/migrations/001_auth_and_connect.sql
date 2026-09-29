-- InnerWave account profiles and durable Spotify-Connect-style playback state.
-- Run this file once in the Supabase SQL editor.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'InnerWave Listener',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.playback_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active_device_id text,
  state jsonb not null default '{}'::jsonb,
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.playback_sessions enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles for select to authenticated
using ((select auth.uid()) = id);
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles for update to authenticated
using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "playback_sessions_select_own" on public.playback_sessions;
create policy "playback_sessions_select_own" on public.playback_sessions for select to authenticated
using ((select auth.uid()) = user_id);
drop policy if exists "playback_sessions_insert_own" on public.playback_sessions;
create policy "playback_sessions_insert_own" on public.playback_sessions for insert to authenticated
with check ((select auth.uid()) = user_id);
drop policy if exists "playback_sessions_update_own" on public.playback_sessions;
create policy "playback_sessions_update_own" on public.playback_sessions for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

grant select, update on public.profiles to authenticated;
grant select, insert, update on public.playback_sessions to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), nullif(new.raw_user_meta_data ->> 'full_name', ''), nullif(new.raw_user_meta_data ->> 'name', ''), split_part(coalesce(new.email, 'InnerWave Listener'), '@', 1)),
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do update set display_name = excluded.display_name, avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url), updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert or update of raw_user_meta_data on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (id, display_name, avatar_url)
select
  id,
  coalesce(nullif(raw_user_meta_data ->> 'display_name', ''), nullif(raw_user_meta_data ->> 'full_name', ''), nullif(raw_user_meta_data ->> 'name', ''), split_part(coalesce(email, 'InnerWave Listener'), '@', 1)),
  nullif(raw_user_meta_data ->> 'avatar_url', '')
from auth.users
on conflict (id) do nothing;

-- Private channel topic format: innerwave:<auth-user-id>:playback
drop policy if exists "innerwave_realtime_receive_own" on realtime.messages;
create policy "innerwave_realtime_receive_own" on realtime.messages for select to authenticated
using (
  realtime.messages.extension in ('broadcast', 'presence')
  and split_part((select realtime.topic()), ':', 1) = 'innerwave'
  and split_part((select realtime.topic()), ':', 2) = (select auth.uid())::text
  and split_part((select realtime.topic()), ':', 3) = 'playback'
);
drop policy if exists "innerwave_realtime_send_own" on realtime.messages;
create policy "innerwave_realtime_send_own" on realtime.messages for insert to authenticated
with check (
  realtime.messages.extension in ('broadcast', 'presence')
  and split_part((select realtime.topic()), ':', 1) = 'innerwave'
  and split_part((select realtime.topic()), ':', 2) = (select auth.uid())::text
  and split_part((select realtime.topic()), ':', 3) = 'playback'
);
