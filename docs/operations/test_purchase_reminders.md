# Testing Purchase Reminders

This guide explains how to manually trigger and test purchase reminder notifications.

## Prerequisites

1. Database migrations 013 and 014 must be applied
2. Edge function `send-push-notifications` must be deployed
3. User must have:
   - Push notifications enabled (push token in database)
   - Reminder days preference set (> 0)
   - Unpurchased claimed items
   - Events with dates in the future

## Architecture Overview

The purchase reminder system consists of:

1. **Database Table**: `sent_reminders` - Tracks which reminders have been sent
2. **Profile Column**: `reminder_days` - User's reminder preference (0-30 days)
3. **Function**: `check_and_queue_purchase_reminders()` - Finds eligible reminders and queues them
4. **Function**: `cleanup_old_reminders()` - Removes old reminder records
5. **Cron Job**: Runs daily at 9 AM to check and queue reminders
6. **Edge Function**: `send-push-notifications` - Processes the notification queue

## How It Works

1. User sets `reminder_days` preference in their profile (e.g., 3 days before event)
2. Cron job runs daily at 9 AM, calling `check_and_queue_purchase_reminders()`
3. Function finds all unpurchased claims for events within the reminder window
4. For each eligible claim, it:
   - Calculates days until event
   - Creates notification in `notification_queue`
   - Records in `sent_reminders` to prevent duplicates
5. Push notification cron (runs every minute) picks up queued notifications and sends them

## Manual Testing

### Method 1: Run the Reminder Check Manually

Connect to your Supabase database and run:

```sql
-- Check which reminders would be sent (dry run)
select
  c.id as claim_id,
  c.claimer_id as user_id,
  i.name as item_name,
  e.title as event_title,
  e.event_date,
  p.reminder_days,
  p.display_name,
  extract(day from (e.event_date - now())) as days_until_event
from public.claims c
join public.items i on i.id = c.item_id
join public.lists l on l.id = i.list_id
join public.events e on e.id = l.event_id
join public.profiles p on p.id = c.claimer_id
where
  c.purchased = false
  and p.reminder_days > 0
  and e.event_date is not null
  and e.event_date > now()
  and e.event_date <= (now() + (p.reminder_days || ' days')::interval)
  and not exists (
    select 1
    from public.sent_reminders sr
    where sr.claim_id = c.id and sr.event_id = e.id
  );

-- Actually queue the reminders
select public.check_and_queue_purchase_reminders();

-- Check what was queued
select * from public.notification_queue
where title = 'Purchase Reminder'
order by created_at desc
limit 10;
```

### Method 2: Create Test Data

If you need to create test data to trigger reminders:

```sql
-- Set a user's reminder preference to 7 days
update public.profiles
set reminder_days = 7
where id = 'your-user-id';

-- Create or update an event to be 5 days from now (within the 7-day window)
update public.events
set event_date = now() + interval '5 days'
where id = 'your-event-id';

-- Make sure you have an unpurchased claim
update public.claims
set purchased = false
where id = 'your-claim-id';

-- Clear any previously sent reminders (for testing)
delete from public.sent_reminders
where claim_id = 'your-claim-id';

-- Now run the reminder check
select public.check_and_queue_purchase_reminders();
```

### Method 3: Test Complete Flow End-to-End

```sql
-- 1. Ensure user has push token
select * from public.push_tokens
where user_id = 'your-user-id';

-- 2. Set reminder days
update public.profiles
set reminder_days = 7
where id = 'your-user-id';

-- 3. Create/update event with upcoming date
update public.events
set event_date = now() + interval '5 days'
where id = 'your-event-id';

-- 4. Ensure claim is unpurchased
update public.claims
set purchased = false
where id = 'your-claim-id'
  and claimer_id = 'your-user-id';

-- 5. Clear previous reminders (testing only)
delete from public.sent_reminders
where claim_id = 'your-claim-id';

-- 6. Run reminder check
select public.check_and_queue_purchase_reminders();

-- 7. Check notification was queued
select * from public.notification_queue
where user_id = 'your-user-id'
  and title = 'Purchase Reminder'
order by created_at desc;

-- 8. Trigger push notification processing
select public.trigger_push_notifications();

-- OR call the edge function directly via HTTP
-- POST https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-push-notifications
-- With Authorization header

-- 9. Verify notification was sent
select * from public.notification_queue
where user_id = 'your-user-id'
  and title = 'Purchase Reminder'
  and sent = true
order by created_at desc;
```

## Verify Cron Jobs Are Set Up

Check if cron jobs are scheduled:

```sql
-- View all scheduled jobs
select * from cron.job;

-- Check recent job runs
select * from cron.job_run_details
where jobname = 'check-purchase-reminders'
order by start_time desc
limit 10;
```

If cron jobs are not set up, apply migration 014:

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/014_setup_cron_jobs.sql
```

## Testing Different Reminder Scenarios

### Test 1: Same-Day Reminder (0 days until event)

```sql
update public.events
set event_date = now() + interval '6 hours'
where id = 'your-event-id';

update public.profiles
set reminder_days = 1
where id = 'your-user-id';

select public.check_and_queue_purchase_reminders();

-- Should show: "Today: Purchase [item] for [event]"
select body from public.notification_queue
where title = 'Purchase Reminder'
order by created_at desc limit 1;
```

### Test 2: Next-Day Reminder

```sql
update public.events
set event_date = now() + interval '1 day'
where id = 'your-event-id';

update public.profiles
set reminder_days = 2
where id = 'your-user-id';

-- Clear previous reminder
delete from public.sent_reminders where claim_id = 'your-claim-id';

select public.check_and_queue_purchase_reminders();

-- Should show: "Tomorrow: Purchase [item] for [event]"
select body from public.notification_queue
where title = 'Purchase Reminder'
order by created_at desc limit 1;
```

### Test 3: Multi-Day Reminder

```sql
update public.events
set event_date = now() + interval '5 days'
where id = 'your-event-id';

update public.profiles
set reminder_days = 7
where id = 'your-user-id';

delete from public.sent_reminders where claim_id = 'your-claim-id';

select public.check_and_queue_purchase_reminders();

-- Should show: "5 days: Purchase [item] for [event]"
select body from public.notification_queue
where title = 'Purchase Reminder'
order by created_at desc limit 1;
```

## Troubleshooting

### No Reminders Being Queued

Check each condition:

```sql
-- 1. Is the claim unpurchased?
select purchased from public.claims where id = 'your-claim-id';

-- 2. Does user have reminder_days > 0?
select reminder_days from public.profiles where id = 'your-user-id';

-- 3. Does event have a future date?
select event_date, event_date > now() as is_future
from public.events where id = 'your-event-id';

-- 4. Is event within reminder window?
select
  e.event_date,
  p.reminder_days,
  e.event_date <= (now() + (p.reminder_days || ' days')::interval) as within_window
from public.events e, public.profiles p
where e.id = 'your-event-id' and p.id = 'your-user-id';

-- 5. Has reminder already been sent?
select * from public.sent_reminders
where claim_id = 'your-claim-id' and event_id = 'your-event-id';

-- 6. Does user have push tokens?
select * from public.push_tokens where user_id = 'your-user-id';
```

### Notifications Not Being Sent

```sql
-- Check notification queue
select * from public.notification_queue
where sent = false
order by created_at desc;

-- Check if edge function is deployed
-- Visit: https://supabase.com/dashboard/project/YOUR_PROJECT/functions

-- Manually trigger push notification processing
select public.trigger_push_notifications();

-- Check cron job status
select * from cron.job_run_details
where jobname = 'process-push-notifications'
order by start_time desc
limit 5;
```

### Reset Everything for Testing

```sql
-- Clear all sent reminders
delete from public.sent_reminders;

-- Clear notification queue
delete from public.notification_queue where title = 'Purchase Reminder';

-- Reset reminder preference
update public.profiles set reminder_days = 3 where id = 'your-user-id';

-- Start fresh
select public.check_and_queue_purchase_reminders();
```

## Production Deployment

To enable purchase reminders in production:

1. Apply migrations 013 and 014 to production database
2. Deploy edge function: `supabase functions deploy send-push-notifications`
3. Verify cron jobs are scheduled: `select * from cron.job;`
4. Test with a real user account and push token
5. Monitor: `select * from cron.job_run_details order by start_time desc;`

## Cleanup

The system automatically cleans up:

- Old reminders (7+ days after event) via `cleanup_old_reminders()` cron job
- Reminders when items are marked as purchased (trigger-based)

Manual cleanup if needed:

```sql
-- Clean up old sent reminders
select public.cleanup_old_reminders();

-- Clean up old notifications
select public.cleanup_old_notifications();
```

## Monitoring in Production

```sql
-- How many reminders sent today?
select count(*) from public.sent_reminders
where sent_at::date = current_date;

-- Which users have reminders enabled?
select count(*), avg(reminder_days)
from public.profiles
where reminder_days > 0;

-- Upcoming events that might trigger reminders
select
  e.title,
  e.event_date,
  count(distinct c.claimer_id) as users_with_claims,
  count(c.id) as total_unpurchased_claims
from public.events e
join public.lists l on l.event_id = e.id
join public.items i on i.list_id = l.id
join public.claims c on c.item_id = i.id
where c.purchased = false
  and e.event_date > now()
  and e.event_date <= now() + interval '7 days'
group by e.id, e.title, e.event_date
order by e.event_date;
```
