# Random Receiver Assignment Implementation

## Overview
This feature allows lists to randomly assign not just givers (who buys items) but also receivers (who gets the gift). This is useful for Secret Santa-style events where each giver should only know who they're buying for, and recipients shouldn't see items intended for them.

## Implementation Status: ✅ Core Implementation Complete

### Completed Tasks

#### 1. Database Migration (`038_add_random_receiver_assignment.sql`)
- ✅ Added `items.assigned_recipient_id` column (nullable UUID reference to profiles)
- ✅ Added `lists.random_receiver_assignment_enabled` boolean flag
- ✅ Created `execute_random_receiver_assignment(p_list_id)` RPC function
- ✅ Added indexes for performance
- ✅ Added comprehensive comments

**Key Logic in RPC:**
- Requires at least 2 members (to avoid giver = receiver)
- Only assigns receivers to items that already have givers (claims with assigned_to)
- Randomly selects receiver from eligible members, excluding the giver
- Updates list's `random_assignment_executed_at` timestamp

#### 2. TypeScript Types Updated (`src/types.ts`)
- ✅ Added `random_receiver_assignment_enabled` to `List` type
- ✅ Added `assigned_recipient_id` to `Item` type
- ✅ Added `assigned_to` to `Claim` type (for giver assignment)

#### 3. RPC Function Updated (`supabase/schema/functions/create_list_with_people_updated.sql`)
- ✅ Added `p_random_receiver_assignment_enabled` parameter
- ✅ Inserts new field when creating list

#### 4. RLS Policies (`supabase/schema/policies/items_rls_random_receiver_assignment.sql`)
- ✅ Created new policy: `items_select_with_receiver_assignment`
- ✅ Hides items from assigned recipients (to maintain surprise)
- ✅ Shows items to assigned givers
- ✅ Admins/creators can see all items

**Visibility Rules:**
```
User can see item IF:
  - List has NO receiver assignment: standard visibility rules apply
  - List HAS receiver assignment:
    - User is NOT the assigned_recipient_id (don't show your own gift!)
    - AND user is the giver (claim.assigned_to = user)
         OR user is admin/creator
```

#### 5. UI Updates (`src/screens/CreateListScreen.tsx`)
- ✅ Added `randomReceiverAssignment` state
- ✅ Added UI toggle (only visible when `randomAssignment` is enabled)
- ✅ Shows informational note about feature requirements
- ✅ Passes parameter to `create_list_with_people` RPC

#### 6. Internationalization (`src/i18n/locales/en.ts`)
- ✅ Added translations for:
  - `createList.randomReceiverAssignment.label`
  - `createList.randomReceiverAssignment.desc`
  - `createList.randomReceiverAssignment.noteTitle`
  - `createList.randomReceiverAssignment.note`

---

## What Still Needs to Be Done

### 1. **Run the Migrations**
```bash
# Apply the new migration to your Supabase database
supabase db push
# OR manually run the migration file
```

### 2. **Update Consolidated Schema**
The `supabase/schema_consolidated.sql` file needs to be regenerated to include:
- New columns on `items` and `lists` tables
- New RPC function `execute_random_receiver_assignment`
- Updated RLS policies

### 3. **Trigger Receiver Assignment**
Currently, we have:
- ✅ Function to execute receiver assignment
- ❌ UI/trigger to call this function

**Options:**
- **A) Automatic:** Execute receiver assignment immediately after giver assignment in the same flow
- **B) Manual Button:** Add a "Assign Receivers" button in ListDetailScreen (similar to giver assignment)
- **C) On List Creation:** Automatically execute when items are added (if enabled)

**Recommended: Option B** - Manual button for explicit control

### 4. **Display Receiver Names to Givers**
When a giver views their assigned item, they should see:
- "This gift is for: [Recipient Name]"
- Update `ListDetailScreen` or item display components to show `assigned_recipient_id`

Example:
```typescript
// In item display component
if (list.random_receiver_assignment_enabled && item.assigned_recipient_id) {
  const recipientName = getRecipientName(item.assigned_recipient_id);
  return (
    <Text>For: {recipientName}</Text>
  );
}
```

### 5. **EditListScreen Updates**
Currently users can toggle random assignment settings when editing a list. Consider:
- Should receiver assignment be editable after creation?
- What happens if you toggle it off after items are assigned?
- Should we show "Reassign Receivers" button?

### 6. **Testing Scenarios**

**Critical Tests:**
1. ✅ Create list with receiver assignment enabled
2. ⚠️ Add items to the list
3. ⚠️ Execute giver assignment (random assignment)
4. ⚠️ Execute receiver assignment
5. ⚠️ Verify giver sees item with recipient name
6. ⚠️ Verify recipient does NOT see item
7. ⚠️ Verify other members don't see item
8. ⚠️ Verify admin/creator sees all items

**Edge Cases:**
- Only 2 members (minimum viable)
- Exactly 1 member (should fail gracefully)
- More items than members
- Items without givers (should skip in assignment)
- Re-running assignment (should reassign or error?)

### 7. **Integration with Existing Random Assignment**
Currently the giver assignment happens via RPC or button. Need to decide:
- Should receiver assignment happen at the same time?
- Separate button or combined flow?
- What's the user experience?

**Suggested Flow:**
```
1. Create list with both random assignment features enabled
2. Add items
3. Click "Assign Items" button
   → Assigns givers (existing logic)
   → Then assigns receivers (new logic)
4. Users see their assigned items with recipient names
```

### 8. **Error Handling & Validation**
Add user-facing errors for:
- "Need at least 2 members for receiver assignment"
- "No items to assign receivers to"
- "Execute giver assignment first"

### 9. **Documentation for Users**
Consider adding help text or tooltips explaining:
- What receiver assignment means
- When to use it (Secret Santa scenario)
- How it differs from giver assignment
- Privacy implications

### 10. **Other Language Translations**
Add translations for other supported languages:
- German (de.ts)
- Spanish (es.ts)
- French (fr.ts)
- Italian (it.ts)
- Swedish (sv.ts)

---

## Architecture Decisions Made

### Why Option 1 (Add Column to Items)?
- ✅ Simple, explicit data model
- ✅ Easy to query and debug
- ✅ Works with both assignment modes
- ✅ Clear separation: claims.assigned_to = giver, items.assigned_recipient_id = receiver

### Why RLS Instead of Application Logic?
- ✅ Database-level security (can't bypass)
- ✅ Works across all clients (web, mobile, future)
- ✅ Centralized visibility rules

### Why Separate from Giver Assignment?
- ✅ More flexible (can enable one without the other)
- ✅ Easier to understand and debug
- ✅ Can be executed independently

---

## Database Schema Changes Summary

```sql
-- New columns
ALTER TABLE items ADD COLUMN assigned_recipient_id uuid;
ALTER TABLE lists ADD COLUMN random_receiver_assignment_enabled boolean;

-- New function
CREATE FUNCTION execute_random_receiver_assignment(p_list_id uuid);

-- New policy
CREATE POLICY items_select_with_receiver_assignment ON items;
```

---

## Next Steps Priority

1. **HIGH**: Run migrations on database
2. **HIGH**: Add UI trigger to call `execute_random_receiver_assignment`
3. **HIGH**: Display recipient names to givers
4. **MEDIUM**: Test end-to-end with real data
5. **MEDIUM**: Add error messages and validation
6. **LOW**: Translate to other languages
7. **LOW**: Update EditListScreen for managing settings

---

## Questions to Consider

1. **Workflow:** Should receiver assignment happen automatically after giver assignment, or manually?
2. **Re-assignment:** Can users re-run receiver assignment, or is it one-time?
3. **Mixed Mode:** What if list has random giver assignment but NOT receiver assignment?
4. **Visibility:** Should recipients know an item exists without seeing details, or completely hidden?
5. **Admin View:** Should admins see a mapping of all giver→receiver pairs?

---

## Files Modified

1. `supabase/migrations/038_add_random_receiver_assignment.sql` (new)
2. `supabase/schema/functions/create_list_with_people_updated.sql`
3. `supabase/schema/policies/items_rls_random_receiver_assignment.sql` (new)
4. `src/types.ts`
5. `src/screens/CreateListScreen.tsx`
6. `src/i18n/locales/en.ts`

## Files That Need Updates

1. `supabase/schema_consolidated.sql` (regenerate)
2. `src/screens/ListDetailScreen.tsx` (add receiver assignment button + display)
3. `src/screens/EditListScreen.tsx` (consider adding receiver assignment toggle)
4. `src/i18n/locales/de.ts, es.ts, fr.ts, it.ts, sv.ts` (translations)
