-- ================================================================
-- SAFE MARKETPLACE SCHEMA APPLICATION
-- This file applies marketplace features to the existing database
-- ================================================================

-- Step 1: Add marketplace-specific fields to listing table
ALTER TABLE listing ADD COLUMN IF NOT EXISTS listing_type VARCHAR(20) DEFAULT 'donation';
ALTER TABLE listing ADD COLUMN IF NOT EXISTS stock_quantity INTEGER;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS min_order_quantity INTEGER DEFAULT 1;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT true;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS business_hours TEXT;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();

-- Add constraint for listing type
DO $$
BEGIN
    ALTER TABLE listing DROP CONSTRAINT IF EXISTS check_listing_type;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE listing ADD CONSTRAINT check_listing_type
    CHECK (listing_type IN ('sale', 'donation', 'request'));

-- Step 2: Create orders table
CREATE TABLE IF NOT EXISTS orders (
    id BIGSERIAL PRIMARY KEY,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id UUID REFERENCES users(id) ON DELETE CASCADE,
    business_id UUID REFERENCES users(id) ON DELETE CASCADE,

    -- Delivery details
    delivery_method VARCHAR(20) NOT NULL,
    delivery_address TEXT,
    delivery_coordinates JSONB,

    -- Customer contact
    customer_name VARCHAR(255) NOT NULL,
    customer_phone VARCHAR(20) NOT NULL,
    customer_email VARCHAR(255),

    -- Order details
    special_instructions TEXT,
    order_notes TEXT,

    -- Status and pricing
    status VARCHAR(20) DEFAULT 'pending',
    total_amount DECIMAL(10,2) DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    confirmed_at TIMESTAMP,
    completed_at TIMESTAMP,
    cancelled_at TIMESTAMP
);

-- Step 3: Create order items table
CREATE TABLE IF NOT EXISTS order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT REFERENCES listing(id) ON DELETE SET NULL,

    -- Product snapshot
    product_name VARCHAR(255) NOT NULL,
    product_description TEXT,
    product_image_url TEXT,

    -- Pricing and quantity
    quantity INTEGER NOT NULL DEFAULT 1,
    price_per_unit DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,

    created_at TIMESTAMP DEFAULT NOW()
);

-- Step 4: Create order status history table
CREATE TABLE IF NOT EXISTS order_status_history (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    notes TEXT,
    changed_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Step 5: Create indexes
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_business ON orders(business_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON order_status_history(order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_history_created ON order_status_history(created_at);

CREATE INDEX IF NOT EXISTS idx_listing_type ON listing(listing_type);
CREATE INDEX IF NOT EXISTS idx_listing_available ON listing(is_available);

-- Step 6: Enable RLS on new tables
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;

-- Step 7: Create RLS policies for orders
DROP POLICY IF EXISTS "Customers can view their orders" ON orders;
CREATE POLICY "Customers can view their orders" ON orders
    FOR SELECT USING (
        customer_id = (SELECT id FROM users WHERE auth_id = auth.uid())
        OR business_id = (SELECT id FROM users WHERE auth_id = auth.uid())
    );

DROP POLICY IF EXISTS "Customers can create orders" ON orders;
CREATE POLICY "Customers can create orders" ON orders
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Businesses can update their orders" ON orders;
CREATE POLICY "Businesses can update their orders" ON orders
    FOR UPDATE USING (
        business_id = (SELECT id FROM users WHERE auth_id = auth.uid())
    );

-- Step 8: Create RLS policies for order_items
DROP POLICY IF EXISTS "Users can view order items" ON order_items;
CREATE POLICY "Users can view order items" ON order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_items.order_id
            AND (orders.customer_id = (SELECT id FROM users WHERE auth_id = auth.uid())
                 OR orders.business_id = (SELECT id FROM users WHERE auth_id = auth.uid()))
        )
    );

DROP POLICY IF EXISTS "Users can create order items" ON order_items;
CREATE POLICY "Users can create order items" ON order_items
    FOR INSERT WITH CHECK (true);

-- Step 9: Create RLS policies for order_status_history
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

DROP POLICY IF EXISTS "System can insert order status history" ON order_status_history;
CREATE POLICY "System can insert order status history" ON order_status_history
    FOR INSERT WITH CHECK (true);

-- Step 10: Create trigger for order number generation
DROP FUNCTION IF EXISTS generate_order_number() CASCADE;
CREATE FUNCTION generate_order_number()
RETURNS TRIGGER AS $$
BEGIN
    NEW.order_number := 'ORD-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(NEW.id::TEXT, 6, '0');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_order_number ON orders;
CREATE TRIGGER set_order_number
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION generate_order_number();

-- Step 11: Create trigger for order status history
DROP FUNCTION IF EXISTS track_order_status_change() CASCADE;
CREATE FUNCTION track_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') OR (OLD.status IS DISTINCT FROM NEW.status) THEN
        INSERT INTO order_status_history (order_id, status, notes)
        VALUES (NEW.id, NEW.status, 'Order status changed to ' || NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS order_status_change_trigger ON orders;
CREATE TRIGGER order_status_change_trigger
    AFTER INSERT OR UPDATE OF status ON orders
    FOR EACH ROW
    EXECUTE FUNCTION track_order_status_change();

-- Step 12: Create trigger for updated_at timestamp
DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;
CREATE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_orders_updated_at ON orders;
CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_listing_updated_at ON listing;
CREATE TRIGGER update_listing_updated_at
    BEFORE UPDATE ON listing
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Step 13: Add updated_at trigger for users table
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Done!
-- You can now use the marketplace features
