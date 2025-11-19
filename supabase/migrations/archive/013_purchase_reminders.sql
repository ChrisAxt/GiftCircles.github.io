-- Migration: Purchase Reminder System
-- Adds ability for users to receive reminders to purchase claimed items before events

-- 1. Add reminder_days preference to profiles table
alter table public.profiles
add column if not exists reminder_days integer default 3 check (reminder_days >= 0 and reminder_days <= 30);

comment on column public.profiles.reminder_days is 'Number of days before event to send purchase reminder (0 = disabled)';

-- 2. Create table to track sent reminders (to avoid duplicate reminders)
create table if not exists public.sent_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  claim_id uuid not null references public.claims(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  sent_at timestamp with time zone default now(),
  unique(claim_id, event_id)
);

alter table public.sent_reminders enable row level security;

-- No public access to sent_reminders - only system can access
create policy "No public access to sent reminders"
  on public.sent_reminders for all
  using (false);

create index if not exists idx_sent_reminders_claim_event on public.sent_reminders(claim_id, event_id);
create index if not exists idx_sent_reminders_user_id on public.sent_reminders(user_id);

-- 3. Function to check and queue purchase reminders
create or replace function public.check_and_queue_purchase_reminders()
returns table(reminders_queued int)
language plpgsql
security definer
as $$
declare
  v_reminder record;
  v_count int := 0;
begin
  -- Find all unpurchased claims for upcoming events where reminder should be sent
  for v_reminder in
    select distinct
      c.id as claim_id,
      c.claimer_id as user_id,
      c.item_id,
      i.name as item_name,
      l.id as list_id,
      l.name as list_name,
      e.id as event_id,
      e.title as event_title,
      e.event_date,
      p.reminder_days,
      p.display_name
    from public.claims c
    join public.items i on i.id = c.item_id
    join public.lists l on l.id = i.list_id
    join public.events e on e.id = l.event_id
    join public.profiles p on p.id = c.claimer_id
    where
      -- Claim is not purchased
      c.purchased = false
      -- User has reminders enabled (reminder_days > 0)
      and p.reminder_days > 0
      -- Event has a date
      and e.event_date is not null
      -- Event is in the future
      and e.event_date > now()
      -- Event is within the reminder window
      and e.event_date <= (now() + (p.reminder_days || ' days')::interval)
      -- Haven't sent a reminder for this claim/event combination yet
      and not exists (
        select 1
        from public.sent_reminders sr
        where sr.claim_id = c.id
          and sr.event_id = e.id
      )
      -- User has push tokens (only send if they can receive it)
      and exists (
        select 1
        from public.push_tokens pt
        where pt.user_id = c.claimer_id
      )
  loop
    -- Calculate days until event
    declare
      v_days_until integer;
    begin
      v_days_until := extract(day from (v_reminder.event_date - now()));

      -- Queue the notification
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_reminder.user_id,
        'Purchase Reminder',
        case
          when v_days_until = 0 then 'Today: Purchase "' || v_reminder.item_name || '" for ' || v_reminder.event_title
          when v_days_until = 1 then 'Tomorrow: Purchase "' || v_reminder.item_name || '" for ' || v_reminder.event_title
          else v_days_until || ' days: Purchase "' || v_reminder.item_name || '" for ' || v_reminder.event_title
        end,
        jsonb_build_object(
          'type', 'purchase_reminder',
          'claim_id', v_reminder.claim_id,
          'item_id', v_reminder.item_id,
          'list_id', v_reminder.list_id,
          'event_id', v_reminder.event_id,
          'days_until', v_days_until
        )
      );

      -- Mark reminder as sent
      insert into public.sent_reminders (user_id, claim_id, event_id)
      values (v_reminder.user_id, v_reminder.claim_id, v_reminder.event_id);

      v_count := v_count + 1;
    end;
  end loop;

  return query select v_count;
end;
$$;

-- 4. Cleanup sent_reminders for past events (optional, run periodically)
create or replace function public.cleanup_old_reminders()
returns void
language plpgsql
security definer
as $$
begin
  delete from public.sent_reminders sr
  using public.events e
  where sr.event_id = e.id
    and (e.event_date < now() - interval '7 days' or e.event_date is null);
end;
$$;

-- 5. Also cleanup sent_reminders when an item is marked as purchased
create or replace function public.cleanup_reminder_on_purchase()
returns trigger
language plpgsql
security definer
as $$
begin
  -- If item was marked as purchased, remove any pending reminders
  if NEW.purchased = true and OLD.purchased = false then
    delete from public.sent_reminders
    where claim_id = NEW.id;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trigger_cleanup_reminder_on_purchase on public.claims;
create trigger trigger_cleanup_reminder_on_purchase
  after update on public.claims
  for each row
  when (NEW.purchased = true and OLD.purchased = false)
  execute function public.cleanup_reminder_on_purchase();
