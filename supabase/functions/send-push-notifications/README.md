# Send Push Notifications Edge Function

This edge function processes the notification queue and sends push notifications via Expo's Push API.

## Setup

1. Deploy the function:
   ```bash
   npx supabase functions deploy send-push-notifications
   ```

2. Set up a cron job to run this function periodically (e.g., every minute):

   You can use pg_cron or an external service like Vercel Cron, or trigger it via a webhook.

   ### Using pg_cron (if available):

   ```sql
   -- Enable pg_cron extension
   create extension if not exists pg_cron;

   -- Schedule the function to run every minute
   select cron.schedule(
     'process-push-notifications',
     '* * * * *',  -- every minute
     $$
     select net.http_post(
       url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push-notifications',
       headers := '{"Content-Type": "application/json", "Authorization": "Bearer YOUR_ANON_KEY"}'::jsonb
     );
     $$
   );
   ```

   ### Manual Trigger (for testing):

   ```bash
   curl -X POST https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push-notifications \
     -H "Authorization: Bearer YOUR_ANON_KEY"
   ```

## How it works

1. Database triggers add notifications to the `notification_queue` table when:
   - A new list is created
   - A new item is added to a list
   - An item is claimed

2. This edge function:
   - Fetches unsent notifications from the queue
   - Groups them by user
   - Looks up each user's push tokens
   - Sends notifications via Expo Push API
   - Marks notifications as sent

3. Old sent notifications are cleaned up periodically (7 days)
