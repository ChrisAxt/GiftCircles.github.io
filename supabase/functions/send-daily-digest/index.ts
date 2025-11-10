// Supabase Edge Function to generate and send daily digest notifications
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    // Create Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Get optional hour parameter from request
    const { hour } = await req.json().catch(() => ({}))

    // Call the database function to generate digests
    // This function aggregates activity and queues notifications
    const { data, error } = await supabase.rpc('generate_and_send_daily_digests', {
      p_hour: hour || null
    })

    if (error) {
      console.error('Error generating digests:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to generate digests', details: error.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const digestsQueued = data?.[0]?.digests_sent || 0

    console.log(`Daily digests queued: ${digestsQueued}`)

    // Now trigger the send-push-notifications function to actually send them
    if (digestsQueued > 0) {
      const pushResponse = await fetch(
        `${supabaseUrl}/functions/v1/send-push-notifications`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_ANON_KEY')}`,
            'Content-Type': 'application/json',
          },
        }
      )

      if (!pushResponse.ok) {
        console.error('Error triggering push notifications:', await pushResponse.text())
      } else {
        const pushResult = await pushResponse.json()
        console.log('Push notifications triggered:', pushResult)
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        digests_queued: digestsQueued,
        message: digestsQueued > 0
          ? `Generated ${digestsQueued} daily digest(s)`
          : 'No digests to send for this hour'
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
