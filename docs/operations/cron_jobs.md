# Supabase Cron Jobs Setup

This document contains the SQL commands to set up automated tasks for push notifications and purchase reminders.

## Prerequisites

Make sure the following extensions are enabled:

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;
```

## Job 1: Process Push Notifications (Every Minute)

This job processes the notification queue and sends push notifications via the edge function.

```sql
select cron.schedule(
  job_name := 'process-push-notifications',
  schedule := '* * * * *',
  command := 'select net.http_post(url := ''https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-push-notifications'', headers := ''{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxZ2Frb3ZiYmJpdWRtZ2dkdXZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwNTY1MjEsImV4cCI6MjA3MjYzMjUyMX0.i81E7-w03a1v6BV2FwGpuNRA9tTVWF3nATgJeeO5g1k"}''::jsonb);'
);
```

## Job 2: Check Purchase Reminders (Daily at 9 AM)

This job checks for unpurchased claimed items and queues reminders for users based on their reminder preferences.

```sql
select cron.schedule(
  job_name := 'check-purchase-reminders',
  schedule := '0 9 * * *',
  command := 'select public.check_and_queue_purchase_reminders();'
);
```

## Job 3: Cleanup Old Notifications (Daily at 3 AM)

This job removes old sent notifications (older than 7 days) to keep the database clean.

```sql
select cron.schedule(
  job_name := 'cleanup-old-notifications',
  schedule := '0 3 * * *',
  command := 'select public.cleanup_old_notifications();'
);
```

## Job 4: Cleanup Old Reminders (Daily at 3 AM)

This job removes sent reminders for past events to keep the database clean.

```sql
select cron.schedule(
  job_name := 'cleanup-old-reminders',
  schedule := '0 3 * * *',
  command := 'select public.cleanup_old_reminders();'
);
```

## Verify Scheduled Jobs

To see all scheduled cron jobs:

```sql
select * from cron.job;
```

## Unschedule a Job (if needed)

To remove a scheduled job:

```sql
select cron.unschedule('job-name-here');
```

For example:
```sql
select cron.unschedule('process-push-notifications');
```

## Schedule Explanations

- `* * * * *` = Every minute
- `*/5 * * * *` = Every 5 minutes
- `0 9 * * *` = Every day at 9:00 AM
- `0 3 * * *` = Every day at 3:00 AM
- `0 */6 * * *` = Every 6 hours

## Monitoring

To check if jobs are running:

```sql
select * from cron.job_run_details
order by start_time desc
limit 10;
```

## Notes

- The push notifications job runs every minute to ensure timely delivery
- Purchase reminders run daily at 9 AM (adjust timezone as needed)
- Cleanup jobs run at 3 AM to minimize impact on active users
- All jobs use the service role internally for security
