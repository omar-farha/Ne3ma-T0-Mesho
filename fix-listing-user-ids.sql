-- Fix listing user_id by matching createdBy email to users table
-- This will populate the user_id field for all existing listings

UPDATE listing
SET user_id = users.id
FROM users
WHERE listing.createdBy = users.email
  AND listing.user_id IS NULL;

-- Verify the update
SELECT
  COUNT(*) as total_listings,
  COUNT(user_id) as listings_with_user_id,
  COUNT(*) - COUNT(user_id) as listings_without_user_id
FROM listing;
