-- ================================================================
-- SUPABASE DATABASE SCHEMA FOR NE3MA PROJECT
-- Migration from Clerk to Supabase Auth with 4 User Account Types
-- ================================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ================================================================
-- 1. USERS TABLE
-- ================================================================

-- Drop existing users table if it exists (careful in production!)
-- DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,

  -- Authentication fields (managed by Supabase Auth)
  auth_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,

  -- Account type (individual, restaurant, factory, pharmacy)
  account_type TEXT NOT NULL CHECK (account_type IN ('individual', 'restaurant', 'factory', 'pharmacy')),

  -- Common fields
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- Individual user fields
  name TEXT, -- For individual users
  phone TEXT,

  -- Business user fields
  business_name TEXT, -- For restaurant/factory/pharmacy

  -- Address field (common to all)
  address TEXT NOT NULL,

  -- Image/Avatar paths (stored in Supabase Storage)
  avatar_path TEXT, -- For individual users
  business_image_path TEXT, -- For business users

  -- Profile visibility and status
  is_active BOOLEAN DEFAULT true,
  email_verified BOOLEAN DEFAULT false,

  -- Ensure proper fields based on account type
  CONSTRAINT individual_fields_check CHECK (
    (account_type = 'individual' AND name IS NOT NULL AND business_name IS NULL AND business_image_path IS NULL) OR
    (account_type IN ('restaurant', 'factory', 'pharmacy') AND business_name IS NOT NULL AND name IS NULL AND avatar_path IS NULL)
  )
);

-- Create indexes for performance
CREATE INDEX idx_users_auth_id ON users(auth_id);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_account_type ON users(account_type);
CREATE INDEX idx_users_created_at ON users(created_at);

-- ================================================================
-- 2. UPDATE EXISTING LISTINGS TABLE
-- ================================================================

-- Add user_id column to existing listings table
ALTER TABLE listing ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE;

-- Create index for listings user_id
CREATE INDEX IF NOT EXISTS idx_listing_user_id ON listing(user_id);

-- Note: We'll migrate createdBy data to user_id after users are created
-- For now, keep both columns during transition

-- ================================================================
-- 3. STORAGE BUCKETS
-- ================================================================

-- Create storage buckets for user files
INSERT INTO storage.buckets (id, name, public)
VALUES
  ('user-avatars', 'user-avatars', true),
  ('business-images', 'business-images', true)
ON CONFLICT (id) DO NOTHING;

-- ================================================================
-- 4. ROW LEVEL SECURITY POLICIES
-- ================================================================

-- Enable RLS on users table
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Users can read their own data
CREATE POLICY "Users can read own data" ON users
  FOR SELECT USING (auth_id = auth.uid());

-- Users can update their own data
CREATE POLICY "Users can update own data" ON users
  FOR UPDATE USING (auth_id = auth.uid());

-- Users can insert their own data (during signup)
CREATE POLICY "Users can insert own data" ON users
  FOR INSERT WITH CHECK (auth_id = auth.uid());

-- Public can read basic profile info (for public profiles)
CREATE POLICY "Public can read basic profile info" ON users
  FOR SELECT USING (
    is_active = true AND
    -- Only allow reading specific fields for public access
    true -- We'll control this in the application layer
  );

-- ================================================================
-- 5. LISTINGS TABLE RLS POLICIES
-- ================================================================

-- Enable RLS on listings table (if not already enabled)
ALTER TABLE listing ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can read all active listings" ON listing;
DROP POLICY IF EXISTS "Users can manage own listings" ON listing;
DROP POLICY IF EXISTS "Public can read active listings" ON listing;

-- Public/Users can read all active listings
CREATE POLICY "Public can read active listings" ON listing
  FOR SELECT USING (active = true);

-- Users can insert listings (must be their own)
CREATE POLICY "Users can create own listings" ON listing
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.auth_id = auth.uid()
      AND users.id = listing.user_id
    )
  );

-- Users can update their own listings
CREATE POLICY "Users can update own listings" ON listing
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.auth_id = auth.uid()
      AND users.id = listing.user_id
    )
  );

-- Users can delete their own listings
CREATE POLICY "Users can delete own listings" ON listing
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.auth_id = auth.uid()
      AND users.id = listing.user_id
    )
  );

-- ================================================================
-- 6. STORAGE POLICIES
-- ================================================================

-- User avatars storage policies
CREATE POLICY "Users can upload own avatar" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'user-avatars' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can update own avatar" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'user-avatars' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Public can view avatars" ON storage.objects
  FOR SELECT USING (bucket_id = 'user-avatars');

-- Business images storage policies
CREATE POLICY "Users can upload own business image" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'business-images' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can update own business image" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'business-images' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Public can view business images" ON storage.objects
  FOR SELECT USING (bucket_id = 'business-images');

-- ================================================================
-- 7. FUNCTIONS AND TRIGGERS
-- ================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to auto-update updated_at
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ================================================================
-- 8. HELPER VIEWS
-- ================================================================

-- View for public user profiles (safe data exposure)
CREATE OR REPLACE VIEW public_user_profiles AS
SELECT
  id,
  account_type,
  CASE
    WHEN account_type = 'individual' THEN name
    ELSE business_name
  END as display_name,
  address,
  CASE
    WHEN account_type = 'individual' THEN avatar_path
    ELSE business_image_path
  END as image_path,
  created_at
FROM users
WHERE is_active = true;

-- Grant access to public profiles view
GRANT SELECT ON public_user_profiles TO anon, authenticated;

-- ================================================================
-- NOTES FOR MIGRATION:
-- ================================================================

-- 1. Run this schema in your Supabase SQL editor
-- 2. Update SUPABASE_SERVICE_ROLE_KEY in .env.local with your service role key
-- 3. Set NEXT_PUBLIC_SUPABASE_AUTH_ENABLED=true when ready to switch
-- 4. Migrate existing createdBy emails to user_id after users are created
-- 5. Test thoroughly before removing Clerk completely

-- Example migration query (run after users are created):
-- UPDATE listing
-- SET user_id = (SELECT id FROM users WHERE email = listing.createdBy)
-- WHERE user_id IS NULL AND createdBy IS NOT NULL;