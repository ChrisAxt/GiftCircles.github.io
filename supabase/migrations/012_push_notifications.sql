-- Migration: Push Notifications System
-- Creates infrastructure for sending push notifications on new lists, items, and claims

-- 1. Create push_tokens table
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('ios', 'android', 'web')),
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

alter table public.push_tokens enable row level security;

-- RLS: Users can only manage their own tokens
create policy "Users can view own tokens"
  on public.push_tokens for select
  using (auth.uid() = user_id);

create policy "Users can insert own tokens"
  on public.push_tokens for insert
  with check (auth.uid() = user_id);

create policy "Users can update own tokens"
  on public.push_tokens for update
  using (auth.uid() = user_id);

create policy "Users can delete own tokens"
  on public.push_tokens for delete
  using (auth.uid() = user_id);

-- Index for faster lookups
create index if not exists idx_push_tokens_user_id on public.push_tokens(user_id);

-- 2. Create notifications queue table (for tracking what notifications to send)
create table if not exists public.notification_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  data jsonb,
  sent boolean default false,
  created_at timestamp with time zone default now()
);

alter table public.notification_queue enable row level security;

-- No public access to notification queue - only system can access
create policy "No public access to notification queue"
  on public.notification_queue for all
  using (false);

-- Index for faster processing
create index if not exists idx_notification_queue_sent on public.notification_queue(sent, created_at);
create index if not exists idx_notification_queue_user_id on public.notification_queue(user_id);

-- 3. Function to queue notifications for event members
create or replace function public.queue_notification_for_event_members(
  p_event_id uuid,
  p_exclude_user_id uuid,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
as $$
begin
  -- Insert notification for all event members except the one who triggered the action
  insert into public.notification_queue (user_id, title, body, data)
  select
    em.user_id,
    p_title,
    p_body,
    p_data
  from public.event_members em
  where em.event_id = p_event_id
    and em.user_id != coalesce(p_exclude_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- Only notify users who have push tokens
    and exists (
      select 1 from public.push_tokens pt where pt.user_id = em.user_id
    );
end;
$$;

-- 4. Trigger function for new lists
create or replace function public.notify_new_list()
returns trigger
language plpgsql
security definer
as $$
declare
  v_event_title text;
  v_creator_name text;
begin
  -- Get event title
  select title into v_event_title
  from public.events
  where id = NEW.event_id;

  -- Get creator display name
  select coalesce(display_name, 'Someone') into v_creator_name
  from public.profiles
  where id = NEW.created_by;

  -- Queue notifications for all event members except creator
  perform public.queue_notification_for_event_members(
    NEW.event_id,
    NEW.created_by,
    'New List: ' || NEW.name,
    v_creator_name || ' created a new list in ' || coalesce(v_event_title, 'an event'),
    jsonb_build_object(
      'type', 'new_list',
      'list_id', NEW.id,
      'event_id', NEW.event_id
    )
  );

  return NEW;
end;
$$;

-- 5. Trigger function for new items
create or replace function public.notify_new_item()
returns trigger
language plpgsql
security definer
as $$
declare
  v_list_id uuid;
  v_list_name text;
  v_event_id uuid;
  v_event_title text;
  v_creator_name text;
begin
  -- Get list info
  select l.id, l.name, l.event_id, e.title
  into v_list_id, v_list_name, v_event_id, v_event_title
  from public.lists l
  join public.events e on e.id = l.event_id
  where l.id = NEW.list_id;

  -- Get creator display name
  select coalesce(display_name, 'Someone') into v_creator_name
  from public.profiles
  where id = NEW.created_by;

  -- Queue notifications for all event members except creator
  perform public.queue_notification_for_event_members(
    v_event_id,
    NEW.created_by,
    'New Item: ' || NEW.name,
    v_creator_name || ' added an item to ' || coalesce(v_list_name, 'a list'),
    jsonb_build_object(
      'type', 'new_item',
      'item_id', NEW.id,
      'list_id', v_list_id,
      'event_id', v_event_id
    )
  );

  return NEW;
end;
$$;

-- 6. Trigger function for new claims
create or replace function public.notify_new_claim()
returns trigger
language plpgsql
security definer
as $$
declare
  v_item_name text;
  v_list_id uuid;
  v_list_name text;
  v_event_id uuid;
  v_event_title text;
  v_claimer_name text;
  v_list_owner_id uuid;
begin
  -- Get item, list, and event info
  select
    i.name,
    l.id,
    l.name,
    l.created_by,
    l.event_id,
    e.title
  into
    v_item_name,
    v_list_id,
    v_list_name,
    v_list_owner_id,
    v_event_id,
    v_event_title
  from public.items i
  join public.lists l on l.id = i.list_id
  join public.events e on e.id = l.event_id
  where i.id = NEW.item_id;

  -- Get claimer display name
  select coalesce(display_name, 'Someone') into v_claimer_name
  from public.profiles
  where id = NEW.claimer_id;

  -- Notify the list owner if they have push tokens and aren't the claimer
  if v_list_owner_id is not null and v_list_owner_id != NEW.claimer_id then
    if exists (select 1 from public.push_tokens where user_id = v_list_owner_id) then
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_list_owner_id,
        'Item Claimed',
        v_claimer_name || ' claimed "' || v_item_name || '" from your list',
        jsonb_build_object(
          'type', 'new_claim',
          'claim_id', NEW.id,
          'item_id', NEW.item_id,
          'list_id', v_list_id,
          'event_id', v_event_id
        )
      );
    end if;
  end if;

  return NEW;
end;
$$;

-- 7. Create triggers
drop trigger if exists trigger_notify_new_list on public.lists;
create trigger trigger_notify_new_list
  after insert on public.lists
  for each row
  execute function public.notify_new_list();

drop trigger if exists trigger_notify_new_item on public.items;
create trigger trigger_notify_new_item
  after insert on public.items
  for each row
  execute function public.notify_new_item();

drop trigger if exists trigger_notify_new_claim on public.claims;
create trigger trigger_notify_new_claim
  after insert on public.claims
  for each row
  execute function public.notify_new_claim();

-- 8. Function to process notification queue and send via Expo
-- This should be called periodically (e.g., via cron job or edge function)
create or replace function public.process_notification_queue()
returns table(processed_count int)
language plpgsql
security definer
as $$
declare
  v_notification record;
  v_tokens text[];
  v_count int := 0;
begin
  -- Process unsent notifications (batch by user to avoid duplicate sends)
  for v_notification in
    select distinct on (user_id, title, body)
      id, user_id, title, body, data
    from public.notification_queue
    where sent = false
    order by user_id, title, body, created_at desc
    limit 100
  loop
    -- Get all push tokens for this user
    select array_agg(token) into v_tokens
    from public.push_tokens
    where user_id = v_notification.user_id;

    if array_length(v_tokens, 1) > 0 then
      -- Note: Actual HTTP request to Expo Push API should be done via Edge Function
      -- This just marks as sent for now
      -- In production, you'd use supabase.functions.invoke or pg_net

      -- Mark as sent
      update public.notification_queue
      set sent = true
      where id = v_notification.id;

      v_count := v_count + 1;
    else
      -- No tokens, mark as sent anyway to avoid reprocessing
      update public.notification_queue
      set sent = true
      where id = v_notification.id;
    end if;
  end loop;

  return query select v_count;
end;
$$;

-- 9. Cleanup old sent notifications (optional, can be run periodically)
create or replace function public.cleanup_old_notifications()
returns void
language plpgsql
security definer
as $$
begin
  delete from public.notification_queue
  where sent = true
    and created_at < now() - interval '7 days';
end;
$$;
