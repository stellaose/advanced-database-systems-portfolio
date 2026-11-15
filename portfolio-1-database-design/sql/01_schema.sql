
BEGIN;
DROP SCHEMA IF EXISTS konga CASCADE;
CREATE SCHEMA konga;
SET LOCAL search_path TO konga;

CREATE TABLE customers (
    customer_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    email_address VARCHAR(255) NOT NULL UNIQUE,
    phone_number VARCHAR(20) NOT NULL UNIQUE,
    full_name VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_customers_email_address CHECK (position('@' IN email_address) > 1)
);

CREATE TABLE addresses (
    address_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    customer_id VARCHAR(36) NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    line1 VARCHAR(255) NOT NULL,
    line2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20),
    country VARCHAR(100) NOT NULL DEFAULT 'Nigeria',
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (customer_id, address_id)
);
CREATE UNIQUE INDEX uq_addresses_default ON addresses(customer_id) WHERE is_default;

CREATE TABLE sellers (
    seller_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    business_name VARCHAR(255) NOT NULL,
    email_address VARCHAR(255) NOT NULL UNIQUE,
    commission_rate NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (commission_rate BETWEEN 0 AND 50),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (position('@' IN email_address) > 1)
);

CREATE TABLE categories (
    category_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    parent_id VARCHAR(36) REFERENCES categories(category_id),
    name VARCHAR(150) NOT NULL,
    slug VARCHAR(150) NOT NULL UNIQUE,
    CHECK (parent_id <> category_id)
);

CREATE TABLE brands (
    brand_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    name VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE products (
    product_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    seller_id VARCHAR(36) NOT NULL REFERENCES sellers(seller_id),
    category_id VARCHAR(36) NOT NULL REFERENCES categories(category_id),
    brand_id VARCHAR(36) REFERENCES brands(brand_id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'live', 'delisted')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A variant (product variation) is the specific version available for purchase.
CREATE TABLE product_variants (
    variant_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    product_id VARCHAR(36) NOT NULL REFERENCES products(product_id),
    sku VARCHAR(100) NOT NULL UNIQUE,
    price NUMERIC(12,2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE inventory (
    variant_id VARCHAR(36) PRIMARY KEY REFERENCES product_variants(variant_id),
    quantity_in_store INTEGER NOT NULL DEFAULT 0 CHECK (quantity_in_store >= 0),
    quantity_reserved INTEGER NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    available_qty INTEGER GENERATED ALWAYS AS (quantity_in_store - quantity_reserved) STORED,
    CHECK (quantity_reserved <= quantity_in_store)
);

-- Create the mandatory stock record with each new product variation.
CREATE FUNCTION create_inventory_record() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path = konga, pg_temp AS $$
BEGIN
    INSERT INTO inventory (variant_id) VALUES (NEW.variant_id);
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_create_inventory_record
AFTER INSERT ON product_variants
FOR EACH ROW EXECUTE FUNCTION create_inventory_record();

-- ! A deferred check also prevents deleting the mandatory stock record.
CREATE FUNCTION check_inventory_record() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path = konga, pg_temp AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM product_variants WHERE variant_id = OLD.variant_id)
       AND NOT EXISTS (SELECT 1 FROM inventory WHERE variant_id = OLD.variant_id) THEN
        RAISE EXCEPTION 'Product variation % requires an inventory record', OLD.variant_id
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER trg_check_inventory_record
AFTER DELETE OR UPDATE ON inventory DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_inventory_record();

CREATE TABLE carts (
    cart_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    customer_id VARCHAR(36) NOT NULL REFERENCES customers(customer_id),
    status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'checked_out', 'abandoned')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_carts_open ON carts(customer_id) WHERE status = 'open';

--  # IN_CART relationship and its quantity attribute.
CREATE TABLE cart_items (
    cart_id VARCHAR(36) NOT NULL REFERENCES carts(cart_id) ON DELETE CASCADE,
    variant_id VARCHAR(36) NOT NULL REFERENCES product_variants(variant_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (cart_id, variant_id)
);

CREATE TABLE coupons (
    coupon_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    code VARCHAR(50) NOT NULL UNIQUE,
    discount_type VARCHAR(20) NOT NULL CHECK (discount_type IN ('percentage', 'fixed')),
    discount_value NUMERIC(12,2) NOT NULL CHECK (discount_value > 0),
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ NOT NULL,
    CHECK (valid_to > valid_from),
    CHECK (discount_type <> 'percentage' OR discount_value <= 100)
);

CREATE TABLE orders (
    order_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    customer_id VARCHAR(36) NOT NULL REFERENCES customers(customer_id),
    shipping_address_id VARCHAR(36) NOT NULL,
    coupon_id VARCHAR(36) REFERENCES coupons(coupon_id),
    placed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled')),
    -- * Checkout must calculate this from order items and any applicable coupon
    -- within the same transaction. A CHECK cannot verify a cross-table total.
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    FOREIGN KEY (customer_id, shipping_address_id) REFERENCES addresses(customer_id, address_id)
);

-- ` CONTAINS relationship: retain the price at the time of purchase.
CREATE TABLE order_items (
    order_item_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    order_id VARCHAR(36) NOT NULL REFERENCES orders(order_id),
    variant_id VARCHAR(36) NOT NULL REFERENCES product_variants(variant_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (order_id, variant_id)
);

CREATE TABLE payments (
    payment_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    order_id VARCHAR(36) NOT NULL REFERENCES orders(order_id),
    method VARCHAR(20) NOT NULL CHECK (method IN ('card', 'wallet', 'bank_transfer', 'pay_on_delivery')),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'successful', 'failed')),
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    provider_ref VARCHAR(150) UNIQUE,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (status <> 'successful' OR paid_at IS NOT NULL)
);

CREATE TABLE refunds (
    refund_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    payment_id VARCHAR(36) NOT NULL REFERENCES payments(payment_id),
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE shipments (
    shipment_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    order_id VARCHAR(36) NOT NULL REFERENCES orders(order_id),
    seller_id VARCHAR(36) NOT NULL REFERENCES sellers(seller_id),
    tracking_number VARCHAR(100) NOT NULL UNIQUE,
    fulfilled_by VARCHAR(20) NOT NULL CHECK (fulfilled_by IN ('konga', 'seller')),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'shipped', 'in_transit', 'delivered', 'failed', 'returned')),
    shipped_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    UNIQUE (order_id, seller_id),
    CHECK (delivered_at IS NULL OR (shipped_at IS NOT NULL AND delivered_at >= shipped_at))
);

CREATE TABLE shipment_events (
    event_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    shipment_id VARCHAR(36) NOT NULL REFERENCES shipments(shipment_id) ON DELETE CASCADE,
    event_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    status VARCHAR(30) NOT NULL,
    location VARCHAR(255),
    description TEXT
);

CREATE TABLE reviews (
    review_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    customer_id VARCHAR(36) NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    product_id VARCHAR(36) NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (customer_id, product_id)
);

CREATE TABLE payouts (
    payout_id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    seller_id VARCHAR(36) NOT NULL REFERENCES sellers(seller_id),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    gross_sales NUMERIC(12,2) NOT NULL CHECK (gross_sales >= 0),
    commission NUMERIC(12,2) NOT NULL CHECK (commission >= 0),
    net_amount NUMERIC(12,2) GENERATED ALWAYS AS (gross_sales - commission) STORED,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'failed')),
    paid_at TIMESTAMPTZ,
    CHECK (period_end >= period_start),
    CHECK (commission <= gross_sales),
    CHECK (status <> 'paid' OR paid_at IS NOT NULL),
    UNIQUE (seller_id, period_start, period_end)
);
COMMIT;
