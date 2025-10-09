// Supabase Edge Function to send push notifications via Expo Push API
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send'

interface PushMessage {
  to: string
  title: string
  body: string
  data?: Record<string, any>
  sound?: string
  badge?: number
}

serve(async (req) => {
  try {
    // Create Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Get unsent notifications from queue
    const { data: notifications, error: fetchError } = await supabase
      .from('notification_queue')
      .select('id, user_id, title, body, data')
      .eq('sent', false)
      .order('created_at', { ascending: true })
      .limit(100)

    if (fetchError) {
      console.error('Error fetching notifications:', fetchError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch notifications' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    if (!notifications || notifications.length === 0) {
      return new Response(
        JSON.stringify({ processed: 0, message: 'No notifications to send' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const results = []
    const processedIds: string[] = []

    // Group notifications by user to batch token lookups
    const notificationsByUser = new Map<string, typeof notifications>()
    for (const notif of notifications) {
      if (!notificationsByUser.has(notif.user_id)) {
        notificationsByUser.set(notif.user_id, [])
      }
      notificationsByUser.get(notif.user_id)!.push(notif)
    }

    // Process each user's notifications
    for (const [userId, userNotifications] of notificationsByUser) {
      // Get user's push tokens
      const { data: tokens, error: tokenError } = await supabase
        .from('push_tokens')
        .select('token')
        .eq('user_id', userId)

      if (tokenError) {
        console.error(`Error fetching tokens for user ${userId}:`, tokenError)
        continue
      }

      if (!tokens || tokens.length === 0) {
        // No tokens, mark notifications as sent anyway
        processedIds.push(...userNotifications.map(n => n.id))
        continue
      }

      // Send each notification to all user's devices
      for (const notification of userNotifications) {
        const messages: PushMessage[] = tokens.map(({ token }) => ({
          to: token,
          title: notification.title,
          body: notification.body,
          data: notification.data || {},
          sound: 'default',
        }))

        try {
          const response = await fetch(EXPO_PUSH_URL, {
            method: 'POST',
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: JSON.stringify(messages),
          })

          const result = await response.json()
          console.log(`Expo response for notification ${notification.id}:`, JSON.stringify(result))
          results.push({ notificationId: notification.id, result })

          // Mark as sent
          processedIds.push(notification.id)
        } catch (error) {
          console.error(`Error sending notification ${notification.id}:`, error)
          // Still mark as sent to avoid retry loops
          processedIds.push(notification.id)
        }
      }
    }

    // Mark all processed notifications as sent
    if (processedIds.length > 0) {
      const { error: updateError } = await supabase
        .from('notification_queue')
        .update({ sent: true })
        .in('id', processedIds)

      if (updateError) {
        console.error('Error updating notifications:', updateError)
      }
    }

    return new Response(
      JSON.stringify({
        processed: processedIds.length,
        results: results.length,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
