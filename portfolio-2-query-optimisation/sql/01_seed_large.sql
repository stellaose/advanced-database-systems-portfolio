-- =====================================================================
-- Portfolio 2: synthetic data at realistic scale (Konga simulation)
-- Requires the schema from portfolio-1-database-design/sql/01_schema.sql.
-- Wipes the small Portfolio 1 sample data first. Stable IDs; seeded random data relative to the load time.
-- Approx. rows: customers 20k, addresses 30k, products 20k, variants 50k,
--   orders 150k, order_items ~450k, payments 150k, shipments up to ~450k, reviews 60k
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO konga;

-- Stable UUID-shaped text IDs, with a separate namespace for each entity.
CREATE FUNCTION pg_temp.seed_id(kind INTEGER, n BIGINT) RETURNS VARCHAR(36)
LANGUAGE SQL IMMUTABLE STRICT AS $$
    SELECT lpad(kind::text, 8, '0') || '-0000-4000-8000-' || lpad(n::text, 12, '0');
$$;
SELECT setseed(0.42);

TRUNCATE customers, addresses, sellers, categories, brands, products, product_variants,
         inventory, carts, cart_items, coupons, orders, order_items, payments, refunds,
         shipments, shipment_events, reviews, payouts RESTART IDENTITY CASCADE;

-- Customers (20,000)
INSERT INTO customers (customer_id, email_address, phone_number, full_name, password_hash, created_at)
SELECT pg_temp.seed_id(1, g), 'user' || g || '@example.com',
       '080' || lpad((10000000 + g)::text, 8, '0'),
       'Customer ' || g,
       md5(g::text),
       now() - (random() * 700 || ' days')::interval
FROM generate_series(1, 20000) g ORDER BY g;

-- Addresses (30,000): first 20,000 addresses are the corresponding customers' defaults
INSERT INTO addresses (address_id, customer_id, line1, city, state, postal_code, is_default)
SELECT pg_temp.seed_id(2, g), pg_temp.seed_id(1, CASE WHEN g <= 20000 THEN g ELSE (g % 20000) + 1 END),
       (g % 200 + 1) || ' Sample Street',
       (ARRAY['Ikeja','Lekki','Wuse 2','Garki','Port Harcourt','Ibadan','Kano','Enugu'])[1 + g % 8],
       (ARRAY['Lagos','Lagos','FCT','FCT','Rivers','Oyo','Kano','Enugu'])[1 + g % 8],
       lpad((100000 + g % 899999)::text, 6, '0'),
       g <= 20000
FROM generate_series(1, 30000) g ORDER BY g;

-- Sellers (500)
INSERT INTO sellers (seller_id, business_name, email_address, status, commission_rate)
SELECT pg_temp.seed_id(3, g), 'Seller ' || g || ' Ltd', 'seller' || g || '@example.com',
       CASE WHEN g % 25 = 0 THEN 'suspended' ELSE 'active' END,
       (ARRAY[8,10,10,12,15])[1 + g % 5]
FROM generate_series(1, 500) g ORDER BY g;

-- Categories: 10 top-level (ids 1-10) + 40 children (ids 11-50)
INSERT INTO categories (category_id, parent_id, name, slug)
SELECT pg_temp.seed_id(4, g), NULL, 'Category ' || g, 'category-' || g FROM generate_series(1, 10) g ORDER BY g;
INSERT INTO categories (category_id, parent_id, name, slug)
SELECT pg_temp.seed_id(4, g), pg_temp.seed_id(4, ((g - 11) % 10) + 1), 'Sub-category ' || g, 'sub-category-' || g
FROM generate_series(11, 50) g ORDER BY g;

-- Brands (60)
INSERT INTO brands (brand_id, name) SELECT pg_temp.seed_id(5, g), 'Brand ' || g FROM generate_series(1, 60) g ORDER BY g;

-- Products (20,000). Name pattern: "<adjective> <noun> <n>"
INSERT INTO products (product_id, seller_id, category_id, brand_id, name, description, status, created_at)
SELECT pg_temp.seed_id(6, g), pg_temp.seed_id(3, 1 + (random() * 499)::int),
       pg_temp.seed_id(4, 11 + (random() * 39)::int),
       CASE WHEN g % 10 = 0 THEN NULL ELSE pg_temp.seed_id(5, 1 + (random() * 59)::int) END,
       (ARRAY['Wireless','Premium','Classic','Compact','Smart'])[1 + g % 5] || ' ' ||
       (ARRAY['Phone','Shirt','Sneakers','Blender','Headphones','Laptop','Bag','Watch','Television','Dress'])[1 + g % 10]
         || ' ' || g,
       'Synthetic description for product ' || g,
       CASE WHEN g % 20 = 0 THEN 'draft' WHEN g % 33 = 0 THEN 'delisted' ELSE 'live' END,
       now() - (random() * 700 || ' days')::interval
FROM generate_series(1, 20000) g ORDER BY g;

-- Variants (50,000): every product gets at least one
INSERT INTO product_variants (variant_id, product_id, sku, price)
SELECT pg_temp.seed_id(7, g), pg_temp.seed_id(6, (g % 20000) + 1), 'SKU-' || lpad(g::text, 6, '0'),
       round((500 + random() * 499500)::numeric, 2)
FROM generate_series(1, 50000) g ORDER BY g;

-- The variation trigger already created the inventory records.
UPDATE inventory SET quantity_in_store = (random() * 200)::int;

-- Orders (150,000), placed over the last 365 days
INSERT INTO orders (order_id, customer_id, shipping_address_id, status, total_amount, placed_at)
SELECT pg_temp.seed_id(8, g), pg_temp.seed_id(1, c), pg_temp.seed_id(2, c),                                    -- corresponding default address
       (ARRAY['delivered','delivered','delivered','delivered','delivered','delivered',
              'shipped','processing','pending','cancelled','delivered'])[1 + (random() * 10)::int],
       0,
       now() - (random() * 365 || ' days')::interval
FROM (SELECT g, 1 + (random() * 19999)::int AS c FROM generate_series(1, 150000) g) s;

-- Order items: 1-5 distinct variants per order (average 3)
INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
SELECT o.order_id, v.variant_id, 1 + (right(o.order_id, 12)::bigint + k) % 3, v.price
FROM orders o
JOIN LATERAL generate_series(1, 1 + (right(o.order_id, 12)::bigint % 5)) k ON TRUE
JOIN product_variants v ON v.variant_id = pg_temp.seed_id(7, ((right(o.order_id, 12)::bigint * 7 + k * 13) % 50000) + 1);

-- Order totals from the items
UPDATE orders o SET total_amount = t.total
FROM (SELECT order_id, sum(quantity * unit_price) AS total FROM order_items GROUP BY order_id) t
WHERE t.order_id = o.order_id;

-- One payment per order
INSERT INTO payments (order_id, method, amount, status, provider_ref, paid_at, created_at)
SELECT order_id,
       (ARRAY['card','wallet','bank_transfer','pay_on_delivery'])[1 + right(order_id, 12)::bigint % 4],
       total_amount,
       CASE status WHEN 'pending' THEN 'pending' WHEN 'cancelled' THEN 'failed'
                   ELSE 'successful' END,
       'PAY-' || order_id,
       CASE WHEN status IN ('pending','cancelled') THEN NULL ELSE placed_at + interval '5 minutes' END,
       placed_at
FROM orders ORDER BY order_id;

-- Shipments: one per seller per shipped/delivered order
INSERT INTO shipments (order_id, seller_id, fulfilled_by, status, tracking_number, shipped_at, delivered_at)
SELECT s.order_id, s.seller_id,
       CASE WHEN right(s.seller_id, 12)::bigint % 3 = 0 THEN 'seller' ELSE 'konga' END,
       CASE s.status WHEN 'shipped' THEN 'in_transit' ELSE 'delivered' END,
       'TRK' || lpad((row_number() OVER (ORDER BY s.order_id, s.seller_id))::text, 9, '0'),
       s.placed_at + interval '1 day',
       CASE WHEN s.status = 'shipped' THEN NULL ELSE s.placed_at + interval '3 days' END
FROM (SELECT DISTINCT o.order_id, p.seller_id, o.status, o.placed_at
      FROM orders o
      JOIN order_items oi ON oi.order_id = o.order_id
      JOIN product_variants v ON v.variant_id = oi.variant_id
      JOIN products p ON p.product_id = v.product_id
      WHERE o.status IN ('shipped','delivered')) s;

INSERT INTO shipment_events (shipment_id, status, location, event_time)
SELECT shipment_id, 'picked_up', 'Origin hub', shipped_at FROM shipments;
INSERT INTO shipment_events (shipment_id, status, location, event_time)
SELECT shipment_id, 'delivered', 'Customer address', delivered_at FROM shipments WHERE delivered_at IS NOT NULL;

-- Reviews (60,000), unique (customer, product) pairs
INSERT INTO reviews (customer_id, product_id, rating, comment, created_at)
SELECT pg_temp.seed_id(1, (g % 20000) + 1),
       pg_temp.seed_id(6, ((g * 37 + (g / 20000) * 101) % 20000) + 1),
       (ARRAY[1,2,3,4,4,5,5,5])[1 + (random() * 7)::int],
       'Synthetic review ' || g,
       now() - (random() * 365 || ' days')::interval
FROM generate_series(1, 60000) g ORDER BY g;

COMMIT;
ANALYZE konga.customers, konga.addresses, konga.sellers, konga.categories, konga.brands,
        konga.products, konga.product_variants, konga.inventory, konga.orders,
        konga.order_items, konga.payments, konga.shipments, konga.shipment_events, konga.reviews;

SELECT 'customers' AS tbl, count(*) FROM konga.customers UNION ALL
SELECT 'products', count(*) FROM konga.products UNION ALL
SELECT 'product_variants', count(*) FROM konga.product_variants UNION ALL
SELECT 'orders', count(*) FROM konga.orders UNION ALL
SELECT 'order_items', count(*) FROM konga.order_items UNION ALL
SELECT 'payments', count(*) FROM konga.payments UNION ALL
SELECT 'shipments', count(*) FROM konga.shipments UNION ALL
SELECT 'reviews', count(*) FROM konga.reviews;
