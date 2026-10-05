-- InnerWave listening rooms: group playback, chat, replies, song cards and reactions.
create table if not exists public.listening_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null default 'Listening room',
  host_id uuid not null references auth.users(id) on delete cascade,
  playback_state jsonb not null default '{}'::jsonb,
  revision bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.room_members (
  room_id uuid not null references public.listening_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('host', 'member')),
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table if not exists public.room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.listening_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 2000),
  reply_to uuid references public.room_messages(id) on delete set null,
  song jsonb,
  created_at timestamptz not null default now(),
  check (char_length(btrim(body)) > 0 or song is not null)
);

create table if not exists public.message_reactions (
  message_id uuid not null references public.room_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

create index if not exists room_messages_room_created_idx on public.room_messages(room_id, created_at);
create index if not exists room_members_user_idx on public.room_members(user_id);

alter table public.listening_rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.room_messages enable row level security;
alter table public.message_reactions enable row level security;

create or replace function public.is_room_member(target_room uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.room_members where room_id = target_room and user_id = auth.uid()) $$;

create or replace function public.create_listening_room(p_name text default 'Listening room')
returns public.listening_rooms language plpgsql security definer set search_path = public
as $$
declare created public.listening_rooms; candidate text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  loop
    candidate := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    exit when not exists(select 1 from public.listening_rooms where code = candidate);
  end loop;
  insert into public.listening_rooms(code, name, host_id)
  values(candidate, coalesce(nullif(btrim(p_name), ''), 'Listening room'), auth.uid()) returning * into created;
  insert into public.room_members(room_id, user_id, role) values(created.id, auth.uid(), 'host');
  return created;
end $$;

create or replace function public.join_listening_room(p_code text)
returns public.listening_rooms language plpgsql security definer set search_path = public
as $$
declare joined public.listening_rooms;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into joined from public.listening_rooms where code = upper(btrim(p_code));
  if joined.id is null then raise exception 'Room not found'; end if;
  insert into public.room_members(room_id, user_id) values(joined.id, auth.uid())
  on conflict(room_id, user_id) do update set last_seen = now();
  return joined;
end $$;

drop policy if exists "members read rooms" on public.listening_rooms;
create policy "members read rooms" on public.listening_rooms for select using (public.is_room_member(id));
drop policy if exists "members update room playback" on public.listening_rooms;
create policy "members update room playback" on public.listening_rooms for update using (public.is_room_member(id)) with check (public.is_room_member(id));
drop policy if exists "hosts delete rooms" on public.listening_rooms;
create policy "hosts delete rooms" on public.listening_rooms for delete using (host_id = auth.uid());

drop policy if exists "members read membership" on public.room_members;
create policy "members read membership" on public.room_members for select using (public.is_room_member(room_id));
drop policy if exists "members leave room" on public.room_members;
create policy "members leave room" on public.room_members for delete using (user_id = auth.uid() or exists(select 1 from public.listening_rooms r where r.id = room_id and r.host_id = auth.uid()));
drop policy if exists "members update own presence" on public.room_members;
create policy "members update own presence" on public.room_members for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "members read messages" on public.room_messages;
create policy "members read messages" on public.room_messages for select using (public.is_room_member(room_id));
drop policy if exists "members send messages" on public.room_messages;
create policy "members send messages" on public.room_messages for insert with check (sender_id = auth.uid() and public.is_room_member(room_id));
drop policy if exists "senders delete messages" on public.room_messages;
create policy "senders delete messages" on public.room_messages for delete using (sender_id = auth.uid());

drop policy if exists "members read reactions" on public.message_reactions;
create policy "members read reactions" on public.message_reactions for select using (
  exists(select 1 from public.room_messages m where m.id = message_id and public.is_room_member(m.room_id))
);
drop policy if exists "members add reactions" on public.message_reactions;
create policy "members add reactions" on public.message_reactions for insert with check (
  user_id = auth.uid() and exists(select 1 from public.room_messages m where m.id = message_id and public.is_room_member(m.room_id))
);
drop policy if exists "users remove own reactions" on public.message_reactions;
create policy "users remove own reactions" on public.message_reactions for delete using (user_id = auth.uid());

-- Room members must be able to resolve each other's display name/avatar.
drop policy if exists "room members read shared profiles" on public.profiles;
create policy "room members read shared profiles" on public.profiles for select using (
  id = auth.uid() or exists(
    select 1 from public.room_members mine join public.room_members theirs on theirs.room_id = mine.room_id
    where mine.user_id = auth.uid() and theirs.user_id = profiles.id
  )
);

grant execute on function public.create_listening_room(text) to authenticated;
grant execute on function public.join_listening_room(text) to authenticated;
grant execute on function public.is_room_member(uuid) to authenticated;
grant select, delete on public.listening_rooms to authenticated;
grant update(playback_state, revision, updated_at) on public.listening_rooms to authenticated;
grant select, delete on public.room_members to authenticated;
grant update(last_seen) on public.room_members to authenticated;
grant select, insert, delete on public.room_messages to authenticated;
grant select, insert, delete on public.message_reactions to authenticated;

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_messages') then
    alter publication supabase_realtime add table public.room_messages;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_reactions') then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_members') then
    alter publication supabase_realtime add table public.room_members;
  end if;
end $$;

drop policy if exists "room realtime receive" on realtime.messages;
create policy "room realtime receive" on realtime.messages for select to authenticated using (
  realtime.messages.extension in ('broadcast', 'presence')
  and split_part(realtime.topic(), ':', 1) = 'room'
  and public.is_room_member(split_part(realtime.topic(), ':', 2)::uuid)
);
drop policy if exists "room realtime send" on realtime.messages;
create policy "room realtime send" on realtime.messages for insert to authenticated with check (
  realtime.messages.extension in ('broadcast', 'presence')
  and split_part(realtime.topic(), ':', 1) = 'room'
  and public.is_room_member(split_part(realtime.topic(), ':', 2)::uuid)
);

notify pgrst, 'reload schema';
