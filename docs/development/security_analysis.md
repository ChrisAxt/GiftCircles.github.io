# GiftCircles Schema Security & Functionality Analysis

## 🔒 CRITICAL SECURITY ISSUES

### 1. ❌ RLS NOT FORCED on Core Tables
**Status**: Tables have RLS enabled but NOT FORCED
- This means SECURITY DEFINER functions can bypass RLS
- MAJOR VULNERABILITY: Malicious functions could be created to read/modify data

**Evidence**:
```
public,claims,true,false      <- RLS enabled but not forced
public,event_members,true,false
public,events,true,false
public,items,true,false
```

**Fix Required**:
```sql
ALTER TABLE events FORCE ROW LEVEL SECURITY;
ALTER TABLE event_members FORCE ROW LEVEL SECURITY;
ALTER TABLE lists FORCE ROW LEVEL SECURITY;
ALTER TABLE items FORCE ROW LEVEL SECURITY;
ALTER TABLE claims FORCE ROW LEVEL SECURITY;
```

### 2. ⚠️ Missing Input Validation in RPC Functions

**create_event_and_admin**: No validation for:
- Empty/whitespace title
- Invalid recurrence values (relies on DB constraint)
- Future event_date validation
- XSS in description field

**create_list_with_people**: Minimal validation:
- Uses `trim(p_name)` but allows empty string after trim
- No max length checks
- No validation that viewers/recipients are event members

**join_event**:
- Trims code but allows empty string (returns invalid_join_code)
- Case-insensitive match is good
- No rate limiting on failed attempts

**claim_item**:
- Good: Checks authorization via can_claim_item
- Missing: No check if item already claimed (relies on unique constraint)

### 3. 🔓 Insufficient RLS Policies

**event_members** - Policy Gap:
```
event_members_select: is_member_of_event(event_id)
```
**PROBLEM**: Users can only see members if they're ALREADY a member.
- New members joining can't see existing members immediately
- Realtime subscriptions may not work properly

**items** - Redundant/Conflicting Policies:
- "items_select_visible": can_view_list(list_id)
- "members can select items in their events": Explicit join check
**PROBLEM**: Two SELECT policies - which one applies? Could cause confusion.

**claims** - Authorization Logic:
```
claims_select_by_claimer: (auth.uid() = claimer_id)
```
**PROBLEM**: Users can only see their OWN claims
- How do list owners see who claimed items?
- Admins can't view claims for management

### 4. ⚠️ Data Integrity Concerns

**No Cascading Delete Checks**: Need to verify:
- When event deleted → members, lists, items, claims cascade?
- When list deleted → items, claims cascade?
- When user deleted → orphaned data?

**list_recipients.can_view column**:
- Allows "hidden recipients" (receive list but can't view it)
- **LOGIC FLAW**: If recipient can't view, how do they know it's for them?
- Confusing UX - should be redesigned

**Multiple Visibility Modes**:
- 'event' - all event members
- 'selected' - specific viewers
- 'public' - everyone (?)
- **PROBLEM**: No clear documentation of behavior
- list_exclusions adds another layer - too complex

### 5. 🚨 Missing Rate Limiting

No rate limiting on:
- join_event (can brute force join codes)
- create_event_and_admin (can spam events)
- claim_item (can spam claim attempts)

### 6. ⚠️ Authorization Gaps

**delete_item function**:
- Checks: admin, list owner, item owner
- **MISSING**: What if item has claims? Should it be deletable?
- Function checks v_has_claims but doesn't use it to block deletion

**Claiming Logic**:
```sql
-- can_claim_item checks:
1. User is event member
2. User is NOT list recipient
```
**PROBLEM**:
- What if list has no recipients? Can anyone claim?
- What if user is both event member AND recipient of different lists?

## ✅ GOOD SECURITY PRACTICES

1. ✅ All RPC functions check auth.uid() IS NOT NULL
2. ✅ SECURITY DEFINER functions use explicit auth checks
3. ✅ Policies use helper functions (maintainable)
4. ✅ Profiles have proper insert/update restrictions
5. ✅ user_plans has read-only policy for clients
6. ✅ Uses trim() on user inputs
7. ✅ ON CONFLICT DO NOTHING prevents duplicate errors

## 🎯 FUNCTIONAL ISSUES

### 1. Subscription/Free Tier Logic
```sql
can_create_event:
  - Pro users: unlimited
  - Free users: max 3 events
```
**PROBLEM**: Counts by event_members, not events owned
- User could be member of 100 events but only OWN 1
- Should count: `SELECT count(*) FROM events WHERE owner_id = p_user`

### 2. Hidden Recipients Feature
```sql
list_recipients(list_id, user_id, can_view)
```
**UX PROBLEM**: How does a recipient know they have a list if can_view=false?
- Seems half-baked
- Either show notification OR remove feature

### 3. List Exclusions Complexity
- list_exclusions lets you hide specific lists from specific users
- Combined with visibility modes = very complex logic
- Likely to have bugs/edge cases
- **RECOMMENDATION**: Simplify to just 2 modes: event-wide or selected viewers

### 4. No Audit Trail
- No created_at/updated_at timestamps visible
- No tracking of who modified what
- Can't see claim history (if unclaimed/reclaimed)

## 📊 RELEASE READINESS ASSESSMENT

### 🚫 BLOCKING ISSUES (Must Fix Before Release):

1. **FORCE ROW LEVEL SECURITY on all tables**
2. **Add input validation to all RPC functions**
3. **Fix event_members visibility for new members**
4. **Fix can_create_event counting logic**
5. **Add rate limiting on join_event**

### ⚠️ HIGH PRIORITY (Fix Soon):

1. **Clarify claims visibility** - who can see who claimed what?
2. **Add cascade delete tests** - ensure data integrity
3. **Simplify visibility logic** - too many modes
4. **Add audit timestamps** - created_at, updated_at
5. **Document hidden recipients behavior** or remove it

### 📝 MEDIUM PRIORITY (Post-Launch):

1. Add XSS sanitization for text fields
2. Add max length constraints
3. Add better error messages with codes
4. Add soft deletes for recovery
5. Add admin override capabilities

## 🎯 VERDICT

**NOT READY FOR PRODUCTION RELEASE**

**Risk Level: HIGH**

**Top 3 Must-Fix**:
1. Force RLS on all tables (security)
2. Add input validation (security + UX)
3. Fix member visibility bug (functionality)

**Estimated Effort**: 2-3 days to make release-ready

## 📋 RECOMMENDED ACTION PLAN

### Day 1: Security Hardening
- [ ] Force RLS on all public tables
- [ ] Add comprehensive input validation to RPCs
- [ ] Add basic rate limiting (via triggers or app-level)

### Day 2: Functionality Fixes
- [ ] Fix event_members visibility
- [ ] Fix can_create_event counting
- [ ] Simplify list visibility (remove complexity)
- [ ] Add proper claim visibility rules

### Day 3: Testing & Documentation
- [ ] Update all tests to match new validation
- [ ] Test cascade deletes thoroughly
- [ ] Document all RPC function error codes
- [ ] Add integration tests for edge cases

---

## Test Status Summary

### TypeScript Tests (supabase/tests/db/)
- **Status**: 9 passing / 9 failing
- **Blocker**: Test users need to be created with specific UUIDs
- **Once fixed**: All syntax/logic errors have been resolved

### SQL Tests (supabase/tests/{integrity,policies,rpc,smoke}/)
- **Status**: Need validation fixes in RPC functions
- **Issues**: Tests expect `invalid_parameter` errors that functions don't throw
- **Recommendation**: Either add validation OR update tests to match actual behavior
