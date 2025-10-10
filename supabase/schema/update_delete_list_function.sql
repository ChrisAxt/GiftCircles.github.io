-- Update delete_list function to allow any event member to delete a list
-- if the original creator is no longer in the event

CREATE OR REPLACE FUNCTION public.delete_list(p_list_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_user   uuid := auth.uid();
  v_event  uuid;
  v_owner  uuid;
  v_creator_in_event boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select l.event_id, l.created_by
    into v_event, v_owner
  from public.lists l
  where l.id = p_list_id;

  if v_event is null then
    raise exception 'not_found';
  end if;

  -- Check if user is a member of the event
  if not exists (
    select 1 from public.event_members
    where event_id = v_event
      and user_id = v_user
  ) then
    raise exception 'not_authorized';
  end if;

  -- Check if the original creator is still in the event
  select exists(
    select 1 from public.event_members
    where event_id = v_event
      and user_id = v_owner
  ) into v_creator_in_event;

  -- Allow deletion if:
  -- 1. User is the creator, OR
  -- 2. User is event admin or event owner, OR
  -- 3. Creator is no longer in the event (orphaned list)
  if v_owner = v_user then
    -- User is the creator, allow deletion
    delete from public.lists where id = p_list_id;
    return;
  end if;

  -- Check if user is event admin or event owner
  if exists (
    select 1 from public.event_members em
    join public.events e on e.id = em.event_id
    where em.event_id = v_event
      and em.user_id = v_user
      and (em.role = 'admin' or e.owner_id = v_user)
  ) then
    -- User is admin/owner, allow deletion
    delete from public.lists where id = p_list_id;
    return;
  end if;

  -- Check if creator is no longer in the event
  if not v_creator_in_event then
    -- Creator is gone, any event member can delete
    delete from public.lists where id = p_list_id;
    return;
  end if;

  -- If none of the above conditions are met, user is not authorized
  raise exception 'not_authorized';
end;
$function$;
