-- Remove unique constraint on address field to allow duplicate addresses
-- This allows multiple listings at the same location

-- Drop the unique constraint on the adderss column
ALTER TABLE listing DROP CONSTRAINT IF EXISTS listing_adderss_key;

-- Verify the constraint has been removed
-- You should see no constraint named 'listing_adderss_key' after running this
