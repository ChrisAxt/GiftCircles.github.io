# Claims Stat Card Fix - Final Solution

**Date:** 2025-10-12
**Issue:** "Items Claimed" stat showing other users' claims instead of YOUR claims

## Problem

The stat cards should show:
1. **Active Events** - Count of events you're a member of
2. **Items Claimed** - Count of items **YOU** personally claimed (to buy as gifts)
3. **To Purchase** - Count of items YOU claimed that are **not yet purchased**

The bug was that "Items Claimed" was using data from the RPC function `events_for_current_user()` which counted ALL claims visible to you (including other people's claims on their lists with `visibility = 'event'`).

## Root Cause

In `EventListScreen.tsx`, line 125 was setting `claimsByEvent` from RPC data:
```typescript
claimMap[r.id] = Number(r.claimed_count ?? 0);  // ← Wrong: counts other people's claims
```

The RPC function's `claims` CTE was using `can_view_list()` which returns `true` for event-wide lists, so it counted claims on lists you can VIEW but didn't CREATE.

## Solution

**Changed approach:** Query YOUR claims directly on the client side, just like "To Purchase" already does.

### Client-Side Changes (`src/screens/EventListScreen.tsx`)

1. **Removed RPC-based claim counting** (lines 120-127):
   - Removed `claimMap` initialization from RPC data
   - Removed `setClaimsByEvent(claimMap)` call

2. **Added comprehensive claim query** (lines 187-220):
```typescript
// Get ALL your claims (for "Items Claimed" stat)
const { data: allMyClaims, error: allErr } = listIds.length
  ? await supabase
    .from('claims')
    .select('id,item_id,purchased,items!inner(list_id)')
    .eq('claimer_id', myId)  // ← Only YOUR claims
    .in('items.list_id', listIds)
  : { data: [], error: null as any };

const allClaimsPerEvent: Record<string, number> = {};
const unpurchasedPerEvent: Record<string, number> = {};
(allMyClaims ?? []).forEach((cl: any) => {
  const listId = cl.items?.list_id as string | undefined;
  if (!listId) return;
  if (iAmRecipientOnList.has(listId)) return; // hide recipient lists
  const evId = eventIdByList[listId];
  if (!evId) return;

  // Count all claims
  allClaimsPerEvent[evId] = (allClaimsPerEvent[evId] || 0) + 1;

  // Count unpurchased claims
  if (cl.purchased === false) {
    unpurchasedPerEvent[evId] = (unpurchasedPerEvent[evId] || 0) + 1;
  }
});

setClaimsByEvent(allClaimsPerEvent);
setUnpurchasedByEvent(unpurchasedPerEvent);
```

### Database Changes (`supabase/schema/functions.sql`)

Updated the RPC function's `claims` CTE to only count claims on lists YOU created:
```sql
claims as (
  select l.event_id, count(distinct c.id) as claimed_count
  from lists l
  join items i on i.list_id = l.id
  left join claims c on c.item_id = i.id
  where l.created_by = auth.uid()  -- ← Only your lists
  group by l.event_id
),
```

**Note:** This RPC change is for data correctness, but the stat cards no longer use this field.

## Result

Now the stat cards correctly show:
- ✅ **Items Claimed** = All items YOU claimed across all events (purchased + unpurchased)
- ✅ **To Purchase** = Subset of above where `purchased = false`
- ✅ Both exclude items on lists where you're a recipient (gift surprise preservation)
- ✅ Both exclude other people's claims

## Testing

To verify the fix works:
1. User A claims an item on User B's event-wide list
2. User B should NOT see User A's claim in their "Items Claimed" stat
3. User B should only see their own claims
4. When User B claims/unclaims items, ONLY their stat updates

## Migration

Migration file: `supabase/migrations/027_fix_recipient_claim_visibility.sql`

Apply with:
```sql
-- Run in Supabase SQL Editor (already applied)
CREATE OR REPLACE FUNCTION public.events_for_current_user()
...
```

## Files Changed

1. `src/screens/EventListScreen.tsx` - Query YOUR claims client-side
2. `supabase/schema/functions.sql` - Update RPC to only count claims on lists you created
3. `supabase/migrations/027_fix_recipient_claim_visibility.sql` - Migration file
