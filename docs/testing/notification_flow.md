# Testing Notification Flow

## Quick Test Checklist

### 1. Check Database Setup
```sql
-- Verify notification_queue table exists and has data
SELECT COUNT(*) FROM notification_queue;

-- Check recent notifications
SELECT 
  id,
  user_id,
  title,
  body,
  data->>'type' as notification_type,
  sent,
  created_at
FROM notification_queue
ORDER BY created_at DESC
LIMIT 5;

-- Check push tokens exist
SELECT user_id, platform, created_at 
FROM push_tokens 
ORDER BY created_at DESC;
```

### 2. Test Notification Creation
Create a list with yourself as recipient to trigger notification:

**Via App:**
1. Open an event
2. Create new list
3. Add your own email as recipient
4. Check notification_queue table

**Via SQL:**
```sql
-- Replace with your actual IDs
SELECT add_list_recipient(
  'YOUR_LIST_ID'::uuid,
  'your@email.com'
);

-- Verify notification was created
SELECT * FROM notification_queue 
WHERE sent = false 
ORDER BY created_at DESC 
LIMIT 1;
```

### 3. Trigger Edge Function
```bash
# Option 1: Via Supabase CLI
supabase functions invoke send-push-notifications

# Option 2: Via curl
curl -X POST \
  'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push-notifications' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json'

# Option 3: Via Supabase Dashboard
# Go to Edge Functions → send-push-notifications → Invoke
```

### 4. Verify Notification Sent
```sql
-- Check if notification was marked as sent
SELECT 
  id,
  title,
  sent,
  created_at
FROM notification_queue
ORDER BY created_at DESC
LIMIT 1;
```

### 5. Test App Navigation
1. ✅ Receive notification on device
2. ✅ Tap notification
3. ✅ App opens and navigates to Events tab (home screen)
4. ✅ PendingInvitesCard shows at the top with Accept/Decline buttons
5. ✅ Tap Accept → becomes event member
6. ✅ Card disappears and event appears in your events list

## Common Issues

### No notifications received
**Check:**
- [ ] Push notifications enabled in app (Profile → Settings)
- [ ] Push token exists in `push_tokens` table
- [ ] Notification created in `notification_queue` with `sent = false`
- [ ] Edge function invoked successfully
- [ ] Notification marked as `sent = true` after edge function
- [ ] Expo push service working (check Expo dashboard)

**Debug:**
```sql
-- Get my user ID
SELECT auth.uid();

-- Check my push tokens
SELECT * FROM push_tokens WHERE user_id = auth.uid();

-- Check my notifications
SELECT * FROM notification_queue WHERE user_id = auth.uid();
```

### Notification received but nothing happens
**Check:**
- [ ] App rebuilt with new code (`npm run android` or `npm run ios`)
- [ ] Notification data includes correct fields (type, event_id, etc.)
- [ ] Navigation handler is set up (check console logs)

**Debug:**
- Open React Native debugger
- Look for console logs like `[Notification] Response received:` when tapping notification

### Accept/Decline buttons not visible
**Check:**
- [ ] PendingInvitesCard added to EventListScreen (Events tab)
- [ ] User has pending invites in database
- [ ] Invite status is 'pending' not 'accepted'/'declined'

**Debug:**
```sql
-- Check my pending invites
SELECT 
  ei.id as invite_id,
  ei.status,
  e.title as event_title
FROM event_invites ei
JOIN events e ON e.id = ei.event_id
WHERE ei.invitee_email = (
  SELECT email FROM auth.users WHERE id = auth.uid()
)
AND ei.status = 'pending';
```

## Automated Testing

Create this as a database function to quickly test:

```sql
CREATE OR REPLACE FUNCTION test_notification_flow()
RETURNS TABLE (
  step text,
  result text,
  details jsonb
) AS $$
DECLARE
  v_user_id uuid;
  v_has_token boolean;
  v_pending_count int;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  
  -- Step 1: Check user authenticated
  RETURN QUERY
  SELECT 
    'Authentication'::text,
    CASE WHEN v_user_id IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('user_id', v_user_id);
  
  -- Step 2: Check push token
  SELECT EXISTS(SELECT 1 FROM push_tokens WHERE user_id = v_user_id)
  INTO v_has_token;
  
  RETURN QUERY
  SELECT 
    'Push Token'::text,
    CASE WHEN v_has_token THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('has_token', v_has_token);
  
  -- Step 3: Check pending invites
  SELECT COUNT(*)
  FROM event_invites ei
  JOIN auth.users u ON u.email = ei.invitee_email
  WHERE u.id = v_user_id
    AND ei.status = 'pending'
  INTO v_pending_count;
  
  RETURN QUERY
  SELECT 
    'Pending Invites'::text,
    CASE WHEN v_pending_count > 0 THEN 'PASS' ELSE 'WARN' END,
    jsonb_build_object('count', v_pending_count);
  
  -- Step 4: Check recent notifications
  RETURN QUERY
  SELECT 
    'Recent Notifications'::text,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'WARN' END,
    jsonb_build_object('count', COUNT(*))
  FROM notification_queue
  WHERE user_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run the test
SELECT * FROM test_notification_flow();
```

## Success Criteria

✅ **Complete Success:**
1. Create list with recipient → notification in queue
2. Edge function runs → notification sent to device
3. Tap notification → app navigates to Events tab
4. See PendingInvitesCard at top with Accept/Decline buttons
5. Accept invite → join event as member
6. Card disappears, event appears in your events list

🎉 **You're done when all 6 steps work!**
