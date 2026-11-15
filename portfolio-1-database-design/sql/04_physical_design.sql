
SET search_path TO konga;

CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    o.placed_at,
    o.status,
    o.total_amount,
    c.customer_id,
    c.full_name,
    c.email_address,
    count(oi.order_item_id) AS line_count,
    sum(oi.quantity) AS unit_count
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY
    o.order_id,
    o.placed_at,
    o.status,
    o.total_amount,
    c.customer_id,
    c.full_name,
    c.email_address;

CREATE OR REPLACE VIEW v_seller_sales AS
SELECT p.seller_id, date_trunc('month', o.placed_at) AS month,
       sum(oi.quantity * oi.unit_price) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN product_variants v ON v.variant_id = oi.variant_id
JOIN products p ON p.product_id = v.product_id
WHERE o.status = 'delivered'
GROUP BY p.seller_id, date_trunc('month', o.placed_at);

CREATE OR REPLACE VIEW v_low_stock AS
SELECT
    p.product_id,
    p.name,
    v.sku,
    i.quantity_in_store,
    i.quantity_reserved,
    i.available_qty
FROM inventory i
JOIN product_variants v ON v.variant_id = i.variant_id
JOIN products p ON p.product_id = v.product_id
WHERE i.available_qty < 10;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'konga_app')     THEN CREATE ROLE konga_app NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'konga_support') THEN CREATE ROLE konga_support NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'konga_analyst') THEN CREATE ROLE konga_analyst NOLOGIN; END IF;
END $$;

GRANT USAGE ON SCHEMA konga TO konga_app, konga_support, konga_analyst;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA konga TO konga_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA konga TO konga_app;

GRANT SELECT (customer_id, email_address, phone_number, full_name, is_active, created_at) ON customers TO konga_support;
GRANT SELECT ON orders, order_items, payments, shipments, shipment_events, addresses TO konga_support;

GRANT SELECT ON v_seller_sales, v_low_stock TO konga_analyst;
