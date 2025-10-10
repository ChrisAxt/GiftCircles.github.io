-- Allow any event member to delete lists and items if the creator is no longer in the event
-- This complements the 30-day auto-deletion system for orphaned lists

-- Update delete_list function
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

-- Update delete_item function
CREATE OR REPLACE FUNCTION public.delete_item(p_item_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_row record;
  v_is_admin boolean := false;
  v_is_list_owner boolean := false;
  v_is_item_owner boolean := false;
  v_has_claims boolean := false;
  v_list_creator_in_event boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select i.id, i.created_by as item_creator,
         l.id as list_id, l.created_by as list_creator, l.event_id
    into v_row
  from public.items i
  join public.lists l on l.id = i.list_id
  where i.id = p_item_id;

  if not found then
    raise exception 'not_found';
  end if;

  -- Check if user is a member of the event
  if not exists (
    select 1 from public.event_members
    where event_id = v_row.event_id
      and user_id = v_uid
  ) then
    raise exception 'not_authorized';
  end if;

  v_is_item_owner := (v_row.item_creator = v_uid);
  v_is_list_owner := (v_row.list_creator = v_uid);
  v_is_admin := exists(
    select 1 from public.event_members em
    join public.events e on e.id = em.event_id
    where em.event_id = v_row.event_id
      and em.user_id  = v_uid
      and (em.role = 'admin' or e.owner_id = v_uid)
  );

  -- Check if the list creator is still in the event
  select exists(
    select 1 from public.event_members
    where event_id = v_row.event_id
      and user_id = v_row.list_creator
  ) into v_list_creator_in_event;

  select exists(select 1 from public.claims c where c.item_id = p_item_id) into v_has_claims;

  -- Allow deletion if:
  -- 1. User is item owner, list owner, or admin, OR
  -- 2. List creator is no longer in the event (orphaned list)
  if not (v_is_item_owner or v_is_list_owner or v_is_admin or not v_list_creator_in_event) then
    raise exception 'not_authorized';
  end if;

  -- Only admins and list owners can delete items with claims
  -- Exception: if list creator is gone, any member can delete
  if v_has_claims and not (v_is_admin or v_is_list_owner or not v_list_creator_in_event) then
    raise exception 'has_claims';
  end if;

  delete from public.claims where item_id = p_item_id;
  delete from public.items  where id      = p_item_id;
end;
$function$;
