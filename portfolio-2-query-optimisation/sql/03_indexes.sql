\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO konga;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Q1: Keep each customer’s orders together in date order to support their order history.
CREATE INDEX IF NOT EXISTS idx_orders_customer_placed ON orders (customer_id, placed_at DESC);

-- Q2: Support the date filter used for recent orders.
CREATE INDEX IF NOT EXISTS idx_orders_placed_at ON orders (placed_at);

-- Q3: Support the joins from a seller’s products to their purchased product variations.
CREATE INDEX IF NOT EXISTS idx_products_seller ON products (seller_id);
CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_order_items_variant ON order_items (variant_id);

-- Q4: category filter on live products; partial index on the rare low-stock rows
CREATE INDEX IF NOT EXISTS idx_products_category_live ON products (category_id) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS idx_inventory_low_stock ON inventory (quantity_in_store, variant_id) WHERE quantity_in_store < 10;

-- Q5: substring search needs a trigram GIN index (a B-tree cannot serve ILIKE '%x%')
CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON products USING gin (name gin_trgm_ops);

-- Q6: Index pending orders by date so older ones can be found without scanning every order.
CREATE INDEX IF NOT EXISTS idx_orders_pending_placed ON orders (placed_at) WHERE status = 'pending';

-- Q7: product page reviews, newest first
CREATE INDEX IF NOT EXISTS idx_reviews_product_created ON reviews (product_id, created_at DESC);

COMMIT;
ANALYZE konga.orders, konga.products, konga.product_variants, konga.order_items, konga.inventory, konga.reviews;
