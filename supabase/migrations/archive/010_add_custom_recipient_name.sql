-- Migration: Add custom_recipient_name to lists table
-- This allows lists to have a custom "Other" recipient name that is not tied to a user account

alter table public.lists
add column if not exists custom_recipient_name text;

-- Drop existing overloaded versions to avoid conflicts
drop function if exists public.create_list_with_people(uuid, text, list_visibility, uuid[], uuid[]);
drop function if exists public.create_list_with_people(uuid, text, text, uuid[], uuid[], uuid[]);

-- Create the updated function with custom_recipient_name parameter
create or replace function public.create_list_with_people(
  p_event_id uuid,
  p_name text,
  p_visibility list_visibility,
  p_recipients uuid[],
  p_hidden_recipients uuid[],
  p_viewers uuid[],
  p_custom_recipient_name text default null
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_user uuid;
  v_list_id uuid;
  v_is_member boolean;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- Check membership in event
  select exists(
    select 1 from public.event_members
    where event_id = p_event_id and user_id = v_user
  ) into v_is_member;

  if not v_is_member then
    raise exception 'not_an_event_member';
  end if;

  -- Create list with custom recipient name if provided
  insert into public.lists (event_id, name, created_by, visibility, custom_recipient_name)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'), p_custom_recipient_name)
  returning id into v_list_id;

  -- recipients (per-recipient can_view flag)
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id, can_view)
    select v_list_id, r, not (r = any(coalesce(p_hidden_recipients, '{}')))
    from unnest(p_recipients) as r;
  end if;

  -- explicit viewers (only matters when visibility = 'selected')
  if coalesce(p_visibility, 'event') = 'selected'
     and array_length(p_viewers, 1) is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, v
    from unnest(p_viewers) as v;
  end if;

  return v_list_id;
end;
$$;
