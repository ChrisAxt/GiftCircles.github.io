-- Migration: Fix claimed_count in events_for_current_user to show total claims, not just on user's own lists
-- Date: 2025-01-17
-- Description: The claimed_count was filtering by l.created_by = auth.uid() which only showed claims on lists you created.
--              This fix removes that filter to show ALL claims on ALL lists in the event.

BEGIN;

CREATE OR REPLACE FUNCTION public.events_for_current_user()
 RETURNS TABLE(id uuid, title text, event_date date, join_code text, created_at timestamp with time zone, member_count bigint, total_items bigint, claimed_count bigint, accessible boolean, rownum integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),
  my_events as (
    select e.*
    from events e
    join event_members em on em.event_id = e.id
    join me on me.uid = em.user_id
  ),
  counts as (
    select
      l.event_id,
      count(distinct l.id) as list_count,
      count(i.id)          as total_items
    from lists l
    left join items i on i.list_id = l.id
    group by l.event_id
  ),
  claims as (
    -- Fixed: Remove l.created_by filter to show ALL claims in the event
    select l.event_id, count(distinct c.id) as claimed_count
    from lists l
    join items i on i.list_id = l.id
    left join claims c on c.item_id = i.id
    group by l.event_id
  ),
  ranked as (
    select
      e.id, e.title, e.event_date, e.join_code, e.created_at,
      (select count(*) from event_members em2 where em2.event_id = e.id) as member_count,
      coalesce(ct.total_items, 0) as total_items,
      coalesce(cl.claimed_count, 0) as claimed_count,
      row_number() over (order by e.created_at asc nulls last, e.id) as rownum
    from my_events e
    left join counts ct on ct.event_id = e.id
    left join claims cl on cl.event_id = e.id
  )
  select
    r.id, r.title, r.event_date, r.join_code, r.created_at,
    r.member_count, r.total_items, r.claimed_count,
    (r.rownum <= public.allowed_event_slots()) as accessible,
    r.rownum
  from ranked r
  order by r.created_at desc nulls last, r.id;
$function$;

COMMENT ON FUNCTION public.events_for_current_user() IS
'Returns all events for the current user with counts. claimed_count shows total claims across all lists in the event.';

COMMIT;
