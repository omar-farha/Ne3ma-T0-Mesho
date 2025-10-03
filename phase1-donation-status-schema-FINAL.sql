-- ================================================================
-- PHASE 1: DONATION STATUS TRACKING SYSTEM
-- Database Schema Extensions (FINAL VERSION)
-- ================================================================

-- Add status tracking columns to existing listing table
ALTER TABLE listing ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'available';
ALTER TABLE listing ADD COLUMN IF NOT EXISTS category VARCHAR(50);
ALTER TABLE listing ADD COLUMN IF NOT EXISTS urgency_level VARCHAR(20) DEFAULT 'moderate';
ALTER TABLE listing ADD COLUMN IF NOT EXISTS estimated_delivery_date TIMESTAMP;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS delivery_notes TEXT;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS delivery_photos JSONB;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS donor_id UUID REFERENCES users(id);
ALTER TABLE listing ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMP;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP;

-- Create status history table for tracking changes (using bigint to match listing.id)
CREATE TABLE IF NOT EXISTS listing_status_history (
    id BIGSERIAL PRIMARY KEY,
    listing_id BIGINT REFERENCES listing(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    changed_by UUID REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create donation transactions table (using bigint for listing_id)
CREATE TABLE IF NOT EXISTS donation_transactions (
    id BIGSERIAL PRIMARY KEY,
    listing_id BIGINT REFERENCES listing(id) ON DELETE CASCADE,
    donor_id UUID REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'pending',
    quantity_donated INTEGER,
    pickup_date TIMESTAMP,
    delivery_date TIMESTAMP,
    delivery_address TEXT,
    delivery_method VARCHAR(50),
    notes TEXT,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    review TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create notification table
CREATE TABLE IF NOT EXISTS notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    data JSONB,
    read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_listing_status ON listing(status);
CREATE INDEX IF NOT EXISTS idx_listing_category ON listing(category);
CREATE INDEX IF NOT EXISTS idx_listing_urgency ON listing(urgency_level);
CREATE INDEX IF NOT EXISTS idx_listing_donor ON listing(donor_id);
CREATE INDEX IF NOT EXISTS idx_listing_claimed_at ON listing(claimed_at);

CREATE INDEX IF NOT EXISTS idx_status_history_listing ON listing_status_history(listing_id);
CREATE INDEX IF NOT EXISTS idx_status_history_created ON listing_status_history(created_at);

CREATE INDEX IF NOT EXISTS idx_donations_listing ON donation_transactions(listing_id);
CREATE INDEX IF NOT EXISTS idx_donations_donor ON donation_transactions(donor_id);
CREATE INDEX IF NOT EXISTS idx_donations_recipient ON donation_transactions(recipient_id);
CREATE INDEX IF NOT EXISTS idx_donations_status ON donation_transactions(status);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);

-- Drop existing constraints first (ignore errors if they don't exist)
DO $$
BEGIN
    ALTER TABLE listing DROP CONSTRAINT IF EXISTS check_status;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE listing DROP CONSTRAINT IF EXISTS check_urgency;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE donation_transactions DROP CONSTRAINT IF EXISTS check_donation_status;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

-- Create enum-like constraints
ALTER TABLE listing ADD CONSTRAINT check_status
    CHECK (status IN ('available', 'claimed', 'in_progress', 'completed', 'expired', 'cancelled'));

ALTER TABLE listing ADD CONSTRAINT check_urgency
    CHECK (urgency_level IN ('low', 'moderate', 'high', 'urgent'));

ALTER TABLE donation_transactions ADD CONSTRAINT check_donation_status
    CHECK (status IN ('pending', 'confirmed', 'in_progress', 'completed', 'cancelled'));

-- Add update timestamp trigger for donation_transactions
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_donation_transactions_updated_at ON donation_transactions;
CREATE TRIGGER update_donation_transactions_updated_at
    BEFORE UPDATE ON donation_transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS policies for new tables
ALTER TABLE listing_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE donation_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can read listing status history" ON listing_status_history;
DROP POLICY IF EXISTS "Users can insert status history for their listings" ON listing_status_history;
DROP POLICY IF EXISTS "Users can read their donation transactions" ON donation_transactions;
DROP POLICY IF EXISTS "Users can create donation transactions" ON donation_transactions;
DROP POLICY IF EXISTS "Users can update their donation transactions" ON donation_transactions;
DROP POLICY IF EXISTS "Users can read their notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update their notifications" ON notifications;

-- Status history policies
CREATE POLICY "Users can read listing status history" ON listing_status_history
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM listing
            WHERE listing.id = listing_status_history.listing_id
            AND (listing.user_id = (SELECT id FROM users WHERE auth_id = auth.uid())
                 OR listing.donor_id = (SELECT id FROM users WHERE auth_id = auth.uid()))
        )
    );

CREATE POLICY "Users can insert status history for their listings" ON listing_status_history
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM listing
            WHERE listing.id = listing_status_history.listing_id
            AND (listing.user_id = (SELECT id FROM users WHERE auth_id = auth.uid())
                 OR listing.donor_id = (SELECT id FROM users WHERE auth_id = auth.uid()))
        )
    );

-- Donation transaction policies
CREATE POLICY "Users can read their donation transactions" ON donation_transactions
    FOR SELECT USING (
        donor_id = (SELECT id FROM users WHERE auth_id = auth.uid()) OR
        recipient_id = (SELECT id FROM users WHERE auth_id = auth.uid())
    );

CREATE POLICY "Users can create donation transactions" ON donation_transactions
    FOR INSERT WITH CHECK (
        donor_id = (SELECT id FROM users WHERE auth_id = auth.uid()) OR
        recipient_id = (SELECT id FROM users WHERE auth_id = auth.uid())
    );

CREATE POLICY "Users can update their donation transactions" ON donation_transactions
    FOR UPDATE USING (
        donor_id = (SELECT id FROM users WHERE auth_id = auth.uid()) OR
        recipient_id = (SELECT id FROM users WHERE auth_id = auth.uid())
    );

-- Notification policies
CREATE POLICY "Users can read their notifications" ON notifications
    FOR SELECT USING (user_id = (SELECT id FROM users WHERE auth_id = auth.uid()));

CREATE POLICY "Users can update their notifications" ON notifications
    FOR UPDATE USING (user_id = (SELECT id FROM users WHERE auth_id = auth.uid()));

-- Function to create status history entry
CREATE OR REPLACE FUNCTION create_status_history()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO listing_status_history (listing_id, status, changed_by, notes)
        VALUES (NEW.id, NEW.status, NEW.user_id, 'Status changed from ' || COALESCE(OLD.status, 'none') || ' to ' || NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS listing_status_change_trigger ON listing;

-- Trigger to automatically create status history
CREATE TRIGGER listing_status_change_trigger
    AFTER UPDATE ON listing
    FOR EACH ROW
    EXECUTE FUNCTION create_status_history();

-- Function to send notification
CREATE OR REPLACE FUNCTION send_status_notification()
RETURNS TRIGGER AS $$
BEGIN
    -- Notify listing owner
    IF NEW.status != OLD.status THEN
        INSERT INTO notifications (user_id, type, title, message, data)
        VALUES (
            (SELECT user_id FROM listing WHERE id = NEW.listing_id),
            'status_update',
            'Donation Status Updated',
            'Your donation status has been updated to: ' || NEW.status,
            jsonb_build_object('listing_id', NEW.listing_id, 'new_status', NEW.status)
        );

        -- Notify donor if exists
        IF (SELECT donor_id FROM listing WHERE id = NEW.listing_id) IS NOT NULL THEN
            INSERT INTO notifications (user_id, type, title, message, data)
            VALUES (
                (SELECT donor_id FROM listing WHERE id = NEW.listing_id),
                'status_update',
                'Donation Status Updated',
                'The donation status has been updated to: ' || NEW.status,
                jsonb_build_object('listing_id', NEW.listing_id, 'new_status', NEW.status)
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS status_notification_trigger ON listing_status_history;

-- Trigger for status notifications
CREATE TRIGGER status_notification_trigger
    AFTER INSERT ON listing_status_history
    FOR EACH ROW
    EXECUTE FUNCTION send_status_notification();

-- Insert default statuses for existing listings
UPDATE listing SET status = 'available' WHERE status IS NULL;
UPDATE listing SET urgency_level = 'moderate' WHERE urgency_level IS NULL;