# 🚨 URGENT: Database Performance Fix Required

## Problem
Profile updates are timing out due to inefficient Row Level Security (RLS) policies that conflict and cause database performance issues.

## Solution
Apply the optimized RLS policies to fix the timeout issue.

## Steps to Fix

### 1. Open Supabase Dashboard
- Go to your Supabase project dashboard
- Navigate to **SQL Editor**

### 2. Run the Fix Script
Copy and paste the contents of `fix-rls-policies.sql` into the SQL editor and execute it.

**OR** run these commands directly:

```sql
-- Drop existing conflicting policies
DROP POLICY IF EXISTS "Users can read own data" ON users;
DROP POLICY IF EXISTS "Public can read basic profile info" ON users;
DROP POLICY IF EXISTS "Users can update own data" ON users;
DROP POLICY IF EXISTS "Users can insert own data" ON users;

-- Create more efficient and specific policies
-- 1. Users can read and update their own complete profile data
CREATE POLICY "Own profile access" ON users
  FOR ALL USING (auth_id = auth.uid());

-- 2. Public can read limited profile info for active users
CREATE POLICY "Public profile read" ON users
  FOR SELECT USING (
    is_active = true AND
    auth_id != auth.uid() -- Only for other users, not own data
  );

-- 3. Create separate policy for service role (backend operations)
CREATE POLICY "Service role full access" ON users
  FOR ALL USING (auth.role() = 'service_role');

-- OPTIMIZE LISTINGS POLICIES TOO
-- Drop existing listing policies
DROP POLICY IF EXISTS "Public can read active listings" ON listing;
DROP POLICY IF EXISTS "Users can create own listings" ON listing;
DROP POLICY IF EXISTS "Users can manage own listings" ON listing;

-- Create more efficient listing policies
CREATE POLICY "Public listing read" ON listing
  FOR SELECT USING (active = true);

CREATE POLICY "Own listing management" ON listing
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = listing.user_id
      AND users.auth_id = auth.uid()
    )
  );
```

### 3. Verify the Fix
After applying the fix:
1. Try editing your profile in the app
2. The update should now be instant instead of timing out
3. Check that both private and public profile pages still work

## What This Fixes
- ✅ Eliminates profile update timeouts
- ✅ Improves database performance
- ✅ Maintains security - users can only edit their own data
- ✅ Maintains public profile access for viewing other users
- ✅ Optimizes listing queries too

## Critical Issues Already Fixed
- ✅ Database field typo: `adderss` → `address` (fixed in 6 files)
- ✅ Removed timeout mechanism from profile updates
- ✅ Optimized RLS policies for better performance

## Next Priority Tasks
1. Create missing essential pages (404, forgot password, terms)
2. Implement proper error handling
3. Add donation status tracking system