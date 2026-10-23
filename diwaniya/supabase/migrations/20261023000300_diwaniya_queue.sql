-- Matchmaking marks matched queue rows instead of removing them; the api function clears them afterwards.
alter table public.queue add column if not exists matched_room uuid;

create or replace function public.queue_pick(p_mode text) returns uuid[]
language plpgsql security definer set search_path = '' as $$
declare first public.queue; win int; picked uuid[];
begin
  select * into first from public.queue where mode = p_mode and matched_room is null order by created_at limit 1 for update skip locked;
  if not found then return null; end if;
  win := case when p_mode = 'friendly' then 100000 else 150 + (extract(epoch from now() - first.created_at)::int / 15) * 50 end;
  select array_agg(user_id) into picked from (
    select user_id from public.queue where mode = p_mode and matched_room is null and user_id <> first.user_id and abs(rating - first.rating) <= win
    order by created_at limit 3 for update skip locked) t;
  if picked is null or array_length(picked, 1) < 3 then return null; end if;
  picked := array_prepend(first.user_id, picked);
  update public.queue set matched_room = '00000000-0000-0000-0000-000000000000' where user_id = any(picked);
  return picked;
end $$;
revoke execute on function public.queue_pick(text) from public, anon, authenticated;
