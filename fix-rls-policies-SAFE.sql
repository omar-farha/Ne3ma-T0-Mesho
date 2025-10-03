-- ================================================================
-- FIX RLS POLICIES FOR BETTER PERFORMANCE (SAFE VERSION)
-- ================================================================

-- Drop existing conflicting policies (this will handle duplicates)
DROP POLICY IF EXISTS "Users can read own data" ON users;
DROP POLICY IF EXISTS "Public can read basic profile info" ON users;
DROP POLICY IF EXISTS "Users can update own data" ON users;
DROP POLICY IF EXISTS "Users can insert own data" ON users;
DROP POLICY IF EXISTS "Own profile access" ON users;
DROP POLICY IF EXISTS "Public profile read" ON users;
DROP POLICY IF EXISTS "Service role full access" ON users;

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

-- ================================================================
-- OPTIMIZE LISTINGS POLICIES TOO
-- ================================================================

-- Drop existing listing policies
DROP POLICY IF EXISTS "Public can read active listings" ON listing;
DROP POLICY IF EXISTS "Users can create own listings" ON listing;
DROP POLICY IF EXISTS "Users can manage own listings" ON listing;
DROP POLICY IF EXISTS "Public listing read" ON listing;
DROP POLICY IF EXISTS "Own listing management" ON listing;

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