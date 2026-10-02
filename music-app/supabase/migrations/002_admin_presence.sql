-- InnerWave admin analytics and privacy-aware location presence.
-- Run after 001_auth_and_connect.sql in the Supabase SQL editor.

create table if not exists public.user_presence (
  user_id uuid not null references auth.users(id) on delete cascade,
  email text,
  display_name text not null default 'InnerWave Listener',
  platform text not null default 'Unknown',
  device_id text not null,
  is_listening boolean not null default false,
  current_track jsonb,
  location_permission text not null default 'unavailable',
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  ip_address inet,
  last_seen timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

alter table public.user_presence enable row level security;

drop policy if exists "presence_upsert_own" on public.user_presence;
create policy "presence_upsert_own" on public.user_presence for insert to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "presence_update_own" on public.user_presence;
create policy "presence_update_own" on public.user_presence for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "presence_select_admin" on public.user_presence;
create policy "presence_select_admin" on public.user_presence for select to authenticated
using (lower(coalesce((select auth.jwt()) ->> 'email', '')) = 'harsh.b.mevada@gmail.com');

drop policy if exists "profiles_select_admin" on public.profiles;
create policy "profiles_select_admin" on public.profiles for select to authenticated
using (lower(coalesce((select auth.jwt()) ->> 'email', '')) = 'harsh.b.mevada@gmail.com');

grant select, insert, update on public.user_presence to authenticated;

create index if not exists user_presence_last_seen_idx on public.user_presence (last_seen desc);
create index if not exists user_presence_listening_idx on public.user_presence (is_listening, last_seen desc);
