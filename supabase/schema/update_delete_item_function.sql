-- Update delete_item function to allow any event member to delete an item
-- if the list creator is no longer in the event

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
