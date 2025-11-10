# Claims Visibility Security Fix

**Date:** 2025-10-12
**Issue:** Users were seeing other people's claim counts and "to purchase" numbers on the Events List screen

## Root Causes

### 1. RPC Function Bypassing Visibility Rules
The `events_for_current_user()` function used `SECURITY DEFINER`, which bypasses RLS policies. The function was counting ALL claims across all lists without checking if the user had permission to view those lists.

**Location:** `supabase/schema/functions.sql` lines 1243-1249

**Problem Code:**
```sql
claims as (
  select l.event_id, count(distinct c.id) as claimed_count
  from lists l
  join items i on i.list_id = l.id
  left join claims c on c.item_id = i.id
  group by l.event_id
),
```

### 2. Missing Claimer Filter in Client Query
The "To Purchase" query in EventListScreen was missing an explicit filter for the current user's claims, relying solely on RLS policies that may not work correctly with JOIN queries.

**Location:** `src/screens/EventListScreen.tsx` lines 187-193

**Problem Code:**
```typescript
const { data: unpurchasedClaims } = await supabase
  .from('claims')
  .select('id,item_id,purchased,items!inner(list_id)')
  .eq('purchased', false)
  .in('items.list_id', listIds)  // ← Missing .eq('claimer_id', myId)
```

## Changes Made

### 1. Updated RPC Function (`supabase/schema/functions.sql`)
Changed claim counting to only include lists YOU created:

```sql
claims as (
  select l.event_id, count(distinct c.id) as claimed_count
  from lists l
  join items i on i.list_id = l.id
  left join claims c on c.item_id = i.id
  where l.created_by = auth.uid()
  group by l.event_id
),
```

**Impact:** The "Items Claimed" stat tile now **only shows claim counts for lists YOU created**, not for other people's lists.

**Key insight:** Even with `visibility = 'event'` (where everyone can view/claim items), you should NOT see claim counts on other people's lists. You should only see:
- Who claimed items on YOUR lists (so you know who's buying what for you)
- What YOU personally claimed (shown in "To Purchase" stat)

### 2. Added Explicit Claimer Filter (`src/screens/EventListScreen.tsx`)
Added `.eq('claimer_id', myId)` to ensure only the current user's claims are fetched:

```typescript
const { data: unpurchasedClaims, error: upErr } = listIds.length
  ? await supabase
    .from('claims')
    .select('id,item_id,purchased,items!inner(list_id)')
    .eq('purchased', false)
    .eq('claimer_id', myId)  // ← Added
    .in('items.list_id', listIds)
  : { data: [], error: null as any };
```

**Impact:** The "To Purchase" stat tile now only shows the user's own unpurchased claims.

### 3. Updated Policy Documentation (`supabase/schema/policies.sql`)
Replaced the outdated CSV format with current database policies, including the improved `claims_select_visible` policy that uses `can_view_list()`.

### 4. Created Migration (`supabase/migrations/026_fix_claims_visibility.sql`)
Created a migration file to apply the RPC function fix to the database.

## Security Implications

**Before:** Users could see aggregated claim statistics for ALL lists in their events, including:
- Lists they are recipients of (which should be hidden)
- Lists they are excluded from viewing
- Lists from other members that aren't shared with them

**After:** Users only see claim statistics for:
- Lists they created
- Lists they are explicitly allowed to view (via list_recipients or list_viewers)
- Lists NOT marked with themselves as recipients or in exclusion lists

## Testing Checklist

- [ ] Apply migration: `supabase db push`
- [ ] Verify "Items Claimed" stat shows only visible claims
- [ ] Verify "To Purchase" stat shows only user's own unpurchased claims
- [ ] Test with multiple users in same event
- [ ] Test with recipient lists (should be hidden from recipient)
- [ ] Test with excluded users (excluded users shouldn't see the list's claims)

## Files Changed

1. `supabase/schema/functions.sql` - Updated `events_for_current_user()` RPC
2. `src/screens/EventListScreen.tsx` - Added explicit claimer_id filter
3. `supabase/schema/policies.sql` - Updated with current database policies
4. `supabase/migrations/026_fix_claims_visibility.sql` - Migration file

## Related Policies

- `claims_select_visible` - Uses `can_view_list(list_id_for_item(item_id), auth.uid())`
- `lists_select_visible` - Uses `can_view_list(id, auth.uid())`
- `list_recipients_select` - Uses `can_view_list(list_id, auth.uid())`
