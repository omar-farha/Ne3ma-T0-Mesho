-- Fix RLS policies for order system
-- Run this in your Supabase SQL Editor

-- Allow inserts to order_items table
DROP POLICY IF EXISTS "Users can create order items" ON order_items;
CREATE POLICY "Users can create order items" ON order_items
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_items.order_id
            AND orders.customer_id = (SELECT id FROM users WHERE auth_id = auth.uid())
        )
    );

-- Allow system to insert into order_status_history (for triggers)
DROP POLICY IF EXISTS "Allow system inserts to order_status_history" ON order_status_history;
CREATE POLICY "Allow system inserts to order_status_history" ON order_status_history
    FOR INSERT WITH CHECK (true);

-- Also allow anyone to insert (since triggers run as system)
ALTER TABLE order_status_history DISABLE ROW LEVEL SECURITY;

-- Re-enable with proper policy
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read order status history" ON order_status_history;
CREATE POLICY "Users can read order status history" ON order_status_history
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_status_history.order_id
            AND (orders.customer_id = (SELECT id FROM users WHERE auth_id = auth.uid())
                 OR orders.business_id = (SELECT id FROM users WHERE auth_id = auth.uid()))
        )
    );

-- Allow inserts without authentication check (for triggers)
DROP POLICY IF EXISTS "System can insert order status history" ON order_status_history;
CREATE POLICY "System can insert order status history" ON order_status_history
    FOR INSERT WITH CHECK (true);

-- Fix orders table - allow anonymous orders
DROP POLICY IF EXISTS "Customers can create orders" ON orders;
CREATE POLICY "Customers can create orders" ON orders
    FOR INSERT WITH CHECK (true);  -- Allow anyone to create orders

-- Fix notifications table - allow triggers to insert
-- First check if notifications table exists
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'notifications') THEN
        -- Disable RLS temporarily
        ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;
        -- Re-enable with proper policies
        ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

        DROP POLICY IF EXISTS "Users can read their notifications" ON notifications;
        CREATE POLICY "Users can read their notifications" ON notifications
            FOR SELECT USING (user_id = (SELECT id FROM users WHERE auth_id = auth.uid()));

        DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
        CREATE POLICY "System can insert notifications" ON notifications
            FOR INSERT WITH CHECK (true);  -- Allow system triggers to insert
    END IF;
END $$;
