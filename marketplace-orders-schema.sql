-- ================================================================
-- MARKETPLACE & DONATION HYBRID PLATFORM
-- Order System Database Schema
-- ================================================================

-- Add marketplace-specific fields to listing table
ALTER TABLE listing ADD COLUMN IF NOT EXISTS listing_type VARCHAR(20) DEFAULT 'sale';
ALTER TABLE listing ADD COLUMN IF NOT EXISTS stock_quantity INTEGER;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS min_order_quantity INTEGER DEFAULT 1;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT true;
ALTER TABLE listing ADD COLUMN IF NOT EXISTS business_hours TEXT;

-- Add constraint for listing type
DO $$
BEGIN
    ALTER TABLE listing DROP CONSTRAINT IF EXISTS check_listing_type;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE listing ADD CONSTRAINT check_listing_type
    CHECK (listing_type IN ('sale', 'donation', 'request'));

-- Create orders table
CREATE TABLE IF NOT EXISTS orders (
    id BIGSERIAL PRIMARY KEY,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id UUID REFERENCES users(id) ON DELETE CASCADE,
    business_id UUID REFERENCES users(id) ON DELETE CASCADE,

    -- Delivery details
    delivery_method VARCHAR(20) NOT NULL, -- 'pickup' or 'delivery'
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

-- Create order items table
CREATE TABLE IF NOT EXISTS order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT REFERENCES listing(id) ON DELETE SET NULL,

    -- Product snapshot (in case product is deleted/changed)
    product_name VARCHAR(255) NOT NULL,
    product_description TEXT,
    product_image_url TEXT,

    -- Pricing and quantity
    quantity INTEGER NOT NULL DEFAULT 1,
    price_per_unit DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,

    created_at TIMESTAMP DEFAULT NOW()
);

-- Create order status history table
CREATE TABLE IF NOT EXISTS order_status_history (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    changed_by UUID REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_listing_type ON listing(listing_type);
CREATE INDEX IF NOT EXISTS idx_listing_available ON listing(is_available);
CREATE INDEX IF NOT EXISTS idx_listing_business_user ON listing(user_id, listing_type);

CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_business ON orders(business_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_number ON orders(order_number);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);

CREATE INDEX IF NOT EXISTS idx_order_history_order ON order_status_history(order_id);
CREATE INDEX IF NOT EXISTS idx_order_history_created ON order_status_history(created_at);

-- Add constraints
DO $$
BEGIN
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS check_delivery_method;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE orders ADD CONSTRAINT check_delivery_method
    CHECK (delivery_method IN ('pickup', 'delivery'));

DO $$
BEGIN
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS check_order_status;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE orders ADD CONSTRAINT check_order_status
    CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'cancelled'));

-- Create function to generate order number
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS TEXT AS $$
DECLARE
    new_order_number TEXT;
    counter INTEGER := 0;
BEGIN
    LOOP
        -- Generate order number: ORD-YYYYMMDD-XXXXX
        new_order_number := 'ORD-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 99999)::TEXT, 5, '0');

        -- Check if it exists
        IF NOT EXISTS (SELECT 1 FROM orders WHERE order_number = new_order_number) THEN
            RETURN new_order_number;
        END IF;

        counter := counter + 1;
        IF counter > 10 THEN
            -- Fallback: use timestamp
            new_order_number := 'ORD-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' || LPAD(FLOOR(RANDOM() * 999)::TEXT, 3, '0');
            RETURN new_order_number;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-generate order number
CREATE OR REPLACE FUNCTION set_order_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
        NEW.order_number := generate_order_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_order_number ON orders;
CREATE TRIGGER trigger_set_order_number
    BEFORE INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION set_order_number();

-- Trigger to update order updated_at timestamp
CREATE OR REPLACE FUNCTION update_order_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();

    -- Set status timestamps
    IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
        NEW.confirmed_at := NOW();
    ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        NEW.completed_at := NOW();
    ELSIF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
        NEW.cancelled_at := NOW();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_order_timestamp ON orders;
CREATE TRIGGER trigger_update_order_timestamp
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_order_timestamp();

-- Trigger to create order status history
CREATE OR REPLACE FUNCTION create_order_status_history()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO order_status_history (order_id, status, notes)
        VALUES (NEW.id, NEW.status, 'Order created');
    ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO order_status_history (order_id, status, notes)
        VALUES (NEW.id, NEW.status, 'Status changed from ' || OLD.status || ' to ' || NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_order_status_history ON orders;
CREATE TRIGGER trigger_create_order_status_history
    AFTER INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION create_order_status_history();

-- Trigger to send notification when order is created
CREATE OR REPLACE FUNCTION notify_business_new_order()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO notifications (user_id, type, title, message, data)
        VALUES (
            NEW.business_id,
            'new_order',
            'New Order Received',
            'You have a new order #' || NEW.order_number || ' from ' || NEW.customer_name,
            jsonb_build_object(
                'order_id', NEW.id,
                'order_number', NEW.order_number,
                'customer_name', NEW.customer_name,
                'customer_phone', NEW.customer_phone,
                'delivery_method', NEW.delivery_method
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_notify_business_new_order ON orders;
CREATE TRIGGER trigger_notify_business_new_order
    AFTER INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION notify_business_new_order();

-- RLS Policies
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS "Customers can read their orders" ON orders;
DROP POLICY IF EXISTS "Businesses can read their orders" ON orders;
DROP POLICY IF EXISTS "Customers can create orders" ON orders;
DROP POLICY IF EXISTS "Businesses can update their orders" ON orders;
DROP POLICY IF EXISTS "Users can read order items" ON order_items;
DROP POLICY IF EXISTS "Users can read order status history" ON order_status_history;

-- Orders policies
CREATE POLICY "Customers can read their orders" ON orders
    FOR SELECT USING (customer_id = (SELECT id FROM users WHERE auth_id = auth.uid()));

CREATE POLICY "Businesses can read their orders" ON orders
    FOR SELECT USING (business_id = (SELECT id FROM users WHERE auth_id = auth.uid()));

CREATE POLICY "Customers can create orders" ON orders
    FOR INSERT WITH CHECK (customer_id = (SELECT id FROM users WHERE auth_id = auth.uid()));

CREATE POLICY "Businesses can update their orders" ON orders
    FOR UPDATE USING (business_id = (SELECT id FROM users WHERE auth_id = auth.uid()));

-- Order items policies
CREATE POLICY "Users can read order items" ON order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_items.order_id
            AND (orders.customer_id = (SELECT id FROM users WHERE auth_id = auth.uid())
                 OR orders.business_id = (SELECT id FROM users WHERE auth_id = auth.uid()))
        )
    );

-- Order status history policies
CREATE POLICY "Users can read order status history" ON order_status_history
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_status_history.order_id
            AND (orders.customer_id = (SELECT id FROM users WHERE auth_id = auth.uid())
                 OR orders.business_id = (SELECT id FROM users WHERE auth_id = auth.uid()))
        )
    );

-- Update existing listings to have proper listing_type
UPDATE listing SET listing_type = 'sale' WHERE listing_type IS NULL AND price > 0;
UPDATE listing SET listing_type = 'donation' WHERE listing_type IS NULL AND (price IS NULL OR price = 0);