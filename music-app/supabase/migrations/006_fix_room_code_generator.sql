-- Hotfix for projects where pgcrypto's gen_random_bytes() is unavailable.
-- gen_random_uuid() is available on current Supabase Postgres projects.
create or replace function public.create_listening_room(p_name text default 'Listening room')
returns public.listening_rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  created public.listening_rooms;
  candidate text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  loop
    candidate := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    exit when not exists (
      select 1 from public.listening_rooms where code = candidate
    );
  end loop;

  insert into public.listening_rooms(code, name, host_id)
  values (
    candidate,
    coalesce(nullif(btrim(p_name), ''), 'Listening room'),
    auth.uid()
  )
  returning * into created;

  insert into public.room_members(room_id, user_id, role)
  values(created.id, auth.uid(), 'host');

  return created;
end;
$$;

grant execute on function public.create_listening_room(text) to authenticated;

notify pgrst, 'reload schema';
