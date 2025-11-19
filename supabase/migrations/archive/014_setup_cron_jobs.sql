-- Migration: Setup Cron Jobs for Notifications
-- This sets up all automated tasks for the notification system

-- Enable required extensions
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 1. Create wrapper function for push notifications
create or replace function public.trigger_push_notifications()
returns void
language plpgsql
security definer
as $$
declare
  v_url text;
  v_request_id bigint;
begin
  v_url := 'https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-push-notifications';

  select net.http_post(
    url := v_url,
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxZ2Frb3ZiYmJpdWRtZ2dkdXZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwNTY1MjEsImV4cCI6MjA3MjYzMjUyMX0.i81E7-w03a1v6BV2FwGpuNRA9tTVWF3nATgJeeO5g1k"}'::jsonb
  ) into v_request_id;
end;
$$;

-- 2. Schedule push notifications processing (every minute)
select cron.schedule(
  'process-push-notifications',
  '* * * * *',
  $$SELECT public.trigger_push_notifications();$$
);

-- 3. Schedule purchase reminders check (daily at 9 AM)
select cron.schedule(
  'check-purchase-reminders',
  '0 9 * * *',
  $$SELECT public.check_and_queue_purchase_reminders();$$
);

-- 4. Schedule cleanup of old notifications (daily at 3 AM)
select cron.schedule(
  'cleanup-old-notifications',
  '0 3 * * *',
  $$SELECT public.cleanup_old_notifications();$$
);

-- 5. Schedule cleanup of old reminders (daily at 3 AM)
select cron.schedule(
  'cleanup-old-reminders',
  '0 3 * * *',
  $$SELECT public.cleanup_old_reminders();$$
);
