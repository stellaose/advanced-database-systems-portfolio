-- 
DROP SCHEMA IF EXISTS exp CASCADE;

-- 
CREATE SCHEMA exp;

-- E1 setup
CREATE TABLE exp.ostat AS SELECT order_id, customer_id, status, total_amount, placed_at FROM konga.orders;

-- 
ALTER TABLE exp.ostat SET (autovacuum_enabled = false);

-- 
CREATE INDEX ON exp.ostat (status);

-- 
ANALYZE exp.ostat;

-- A. fresh statistics ('returned' is about 5% of rows)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'returned';

-- E1: data distribution changes (about 70% become 'returned'); statistics NOT refreshed
UPDATE exp.ostat SET status = 'returned' WHERE order_id % 10 < 7;

-- B. STALE statistics after the data changed
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'returned';

-- E1: refresh statistics
ANALYZE exp.ostat;

-- C. after ANALYZE (statistics refreshed)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'returned';

-- E2a IN (subquery)
EXPLAIN (ANALYZE, BUFFERS) SELECT customer_id, full_name FROM konga.customers WHERE customer_id IN (SELECT customer_id FROM konga.orders WHERE placed_at >= now() - interval '7 days');

-- E2a EXISTS (correlated)
EXPLAIN (ANALYZE, BUFFERS) SELECT c.customer_id, c.full_name FROM konga.customers c WHERE EXISTS (SELECT 1 FROM konga.orders o WHERE o.customer_id = c.customer_id AND o.placed_at >= now() - interval '7 days');

-- E2a JOIN + DISTINCT
EXPLAIN (ANALYZE, BUFFERS) SELECT DISTINCT c.customer_id, c.full_name FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.placed_at >= now() - interval '7 days';

-- E2b correlated subquery per row
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, (SELECT sum(i.quantity * i.unit_price) FROM konga.order_items i WHERE i.order_id = o.order_id) AS total FROM konga.orders o WHERE o.customer_id < 3000;

-- E2b join + GROUP BY (rewritten)
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(i.quantity * i.unit_price) AS total FROM konga.orders o LEFT JOIN konga.order_items i ON i.order_id = o.order_id WHERE o.customer_id < 3000 GROUP BY o.order_id;

-- E2c function on column: date_trunc('day', placed_at) = DATE
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM konga.orders WHERE date_trunc('day', placed_at) = date_trunc('day', now() - interval '30 days');

-- E2c range on the bare column (rewritten)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM konga.orders WHERE placed_at >= date_trunc('day', now() - interval '30 days') AND placed_at < date_trunc('day', now() - interval '29 days');

-- E3 selective (customer_id < 300, about 1.5% of orders) / optimiser's choice
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < 300 GROUP BY o.order_id;

-- 
SET enable_nestloop = off;

-- 
SET enable_mergejoin = off;

-- E3 selective (customer_id < 300, about 1.5% of orders) / force hash join
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < 300 GROUP BY o.order_id;

-- 
RESET enable_nestloop;

-- 
RESET enable_mergejoin;

-- 
SET enable_nestloop = off;

-- 
SET enable_hashjoin = off;

-- E3 selective (customer_id < 300, about 1.5% of orders) / force merge join
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < 300 GROUP BY o.order_id;

-- 
RESET enable_nestloop;

-- 
RESET enable_hashjoin;

-- 
SET enable_hashjoin = off;

-- 
SET enable_mergejoin = off;

-- E3 selective (customer_id < 300, about 1.5% of orders) / force nested loop
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < 300 GROUP BY o.order_id;

-- 
RESET enable_hashjoin;

-- 
RESET enable_mergejoin;

-- E3 broad (customer_id < 15000, about 75% of orders) / optimiser's choice
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < 15000 GROUP BY o.order_id;

-- 
SET enable_nestloop = off;

-- 
SET enable_mergejoin = off;

-- E3 broad (customer_id < 15000, about 75% of orders) / force hash join
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < 15000 GROUP BY o.order_id;

-- 
RESET enable_nestloop;

-- 
RESET enable_mergejoin;

-- 
SET enable_nestloop = off;

-- 
SET enable_hashjoin = off;

-- E3 broad (customer_id < 15000, about 75% of orders) / force merge join
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < 15000 GROUP BY o.order_id;

-- 
RESET enable_nestloop;

-- 
RESET enable_hashjoin;

-- 
SET enable_hashjoin = off;

-- 
SET enable_mergejoin = off;

-- E3 broad (customer_id < 15000, about 75% of orders) / force nested loop
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < 15000 GROUP BY o.order_id;

-- 
RESET enable_hashjoin;

-- 
RESET enable_mergejoin;

-- E4 setup
CREATE TABLE exp.p4 AS SELECT payment_id, order_id, method, status, amount, created_at FROM konga.payments;

-- 
ANALYZE exp.p4;

-- 
VACUUM ANALYZE exp.p4;

-- 1. no index (heap scan)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- 
CREATE INDEX i_single ON exp.p4 (method);

-- 
VACUUM ANALYZE exp.p4;

-- 2. single-column B-tree (method)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- 
DROP INDEX exp.i_single;

-- 
CREATE INDEX i_hash ON exp.p4 USING hash (method);

-- 
VACUUM ANALYZE exp.p4;

-- 3. hash index (method)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- 
DROP INDEX exp.i_hash;

-- 
CREATE INDEX i_multi ON exp.p4 (method, status, created_at DESC);

-- 
VACUUM ANALYZE exp.p4;

-- 4. multi-column B-tree (method, status, created_at DESC)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- 
DROP INDEX exp.i_multi;

-- 
CREATE INDEX i_cover ON exp.p4 (method, status, created_at DESC) INCLUDE (payment_id, amount);

-- 
VACUUM ANALYZE exp.p4;

-- 5. covering (same keys + INCLUDE payment_id, amount)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- Q8 on base tables (join + aggregate every time)
EXPLAIN (ANALYZE, BUFFERS) SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.status NOT IN ('cancelled','returned') GROUP BY c.customer_id, c.full_name ORDER BY lifetime_value DESC LIMIT 10;

-- E5 materialised view
CREATE MATERIALIZED VIEW exp.mv_customer_ltv AS SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.status NOT IN ('cancelled','returned') GROUP BY c.customer_id, c.full_name;

-- 
CREATE INDEX ON exp.mv_customer_ltv (lifetime_value DESC);

-- 
ANALYZE exp.mv_customer_ltv;

-- Q8 from the materialised view
EXPLAIN (ANALYZE, BUFFERS) SELECT customer_id, full_name, orders, lifetime_value FROM exp.mv_customer_ltv ORDER BY lifetime_value DESC LIMIT 10;

-- E5 refresh cost
REFRESH MATERIALIZED VIEW exp.mv_customer_ltv;

-- Seller x month revenue report on base tables
EXPLAIN (ANALYZE, BUFFERS) SELECT p.seller_id, date_trunc('month', o.placed_at) AS month, sum(oi.quantity * oi.unit_price) AS revenue FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id JOIN konga.product_variants v ON v.variant_id = oi.variant_id JOIN konga.products p ON p.product_id = v.product_id WHERE o.status = 'delivered' GROUP BY p.seller_id, date_trunc('month', o.placed_at) ORDER BY 1, 2 LIMIT 20;

-- E5 materialised view 2
CREATE MATERIALIZED VIEW exp.mv_seller_revenue AS SELECT p.seller_id, date_trunc('month', o.placed_at) AS month, sum(oi.quantity * oi.unit_price) AS revenue FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id JOIN konga.product_variants v ON v.variant_id = oi.variant_id JOIN konga.products p ON p.product_id = v.product_id WHERE o.status = 'delivered' GROUP BY p.seller_id, date_trunc('month', o.placed_at);

-- 
CREATE INDEX ON exp.mv_seller_revenue (seller_id, month);

-- 
ANALYZE exp.mv_seller_revenue;

-- Seller x month revenue from the materialised view
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.mv_seller_revenue ORDER BY seller_id, month LIMIT 20;

-- 
SET max_parallel_workers_per_gather = 0;

-- max_parallel_workers_per_gather = 0
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000;

-- 
SET max_parallel_workers_per_gather = 1;

-- max_parallel_workers_per_gather = 1
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000;

-- 
SET max_parallel_workers_per_gather = 2;

-- max_parallel_workers_per_gather = 2
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000;

-- 
SET max_parallel_workers_per_gather = 4;

-- max_parallel_workers_per_gather = 4
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000;

-- 
RESET max_parallel_workers_per_gather;

-- 
SET work_mem = '64kB';

-- 
SET max_parallel_workers_per_gather = 0;

-- ORDER BY over 150,000 rows, work_mem = 64kB
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC;

-- 
SET work_mem = '1MB';

-- 
SET max_parallel_workers_per_gather = 0;

-- ORDER BY over 150,000 rows, work_mem = 1MB
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC;

-- 
SET work_mem = '4MB';

-- 
SET max_parallel_workers_per_gather = 0;

-- ORDER BY over 150,000 rows, work_mem = 4MB
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC;

-- 
SET work_mem = '64MB';

-- 
SET max_parallel_workers_per_gather = 0;

-- ORDER BY over 150,000 rows, work_mem = 64MB
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC;

-- 
RESET work_mem;

-- 
RESET max_parallel_workers_per_gather;

-- E7 setup: physically sorted by order_id
CREATE TABLE exp.items_seq AS SELECT * FROM konga.order_items ORDER BY order_id;

-- E7 setup: random physical order (unordered heap)
CREATE TABLE exp.items_heap AS SELECT * FROM konga.order_items ORDER BY random();

-- 
ANALYZE exp.items_seq;

-- 
ANALYZE exp.items_heap;

-- 
ANALYZE exp.items_heap;

-- E7 Heap (unordered), no index / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_heap WHERE order_id = 77777;

-- E7 Heap (unordered), no index / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_heap WHERE order_id BETWEEN 70000 AND 71500;

-- 
CREATE INDEX ih_btree ON exp.items_heap (order_id);

-- 
ANALYZE exp.items_heap;

-- E7 Heap + B-tree index (indexed organisation, scattered rows) / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_heap WHERE order_id = 77777;

-- E7 Heap + B-tree index (indexed organisation, scattered rows) / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_heap WHERE order_id BETWEEN 70000 AND 71500;

-- 
DROP INDEX exp.ih_btree; CREATE INDEX ih_hash ON exp.items_heap USING hash (order_id);

-- 
ANALYZE exp.items_heap;

-- E7 Heap + hash index / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_heap WHERE order_id = 77777;

-- E7 Heap + hash index / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_heap WHERE order_id BETWEEN 70000 AND 71500;

-- 
DROP INDEX exp.ih_hash;

-- 
CREATE INDEX ih_btree2 ON exp.items_heap (order_id);

-- E7: CLUSTER = physically sort the table by the index key (sequential / clustered organisation)
CLUSTER exp.items_heap USING ih_btree2;

-- 
ANALYZE exp.items_heap;

-- E7 Clustered on order_id + B-tree / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_heap WHERE order_id = 77777;

-- E7 Clustered on order_id + B-tree / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_heap WHERE order_id BETWEEN 70000 AND 71500;

-- 
DROP INDEX exp.ih_btree2;

-- 
CREATE INDEX is_brin ON exp.items_seq USING brin (order_id);

-- 
ANALYZE exp.items_seq;

-- E7 Sorted table + BRIN index (block-range) / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_seq WHERE order_id = 77777;

-- E7 Sorted table + BRIN index (block-range) / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_seq WHERE order_id BETWEEN 70000 AND 71500;

-- E9 q1_customer_order_history
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, placed_at, status, total_amount
FROM konga.orders
WHERE customer_id = 12345
ORDER BY placed_at DESC;

-- E9 q2_top_selling_90_days
EXPLAIN (ANALYZE, BUFFERS) SELECT oi.variant_id, v.sku, sum(oi.quantity) AS units_sold
FROM konga.orders o
JOIN konga.order_items oi ON oi.order_id = o.order_id
JOIN konga.product_variants v ON v.variant_id = oi.variant_id
WHERE o.placed_at >= now() - interval '90 days'
  AND o.status <> 'cancelled'
GROUP BY oi.variant_id, v.sku
ORDER BY units_sold DESC
LIMIT 10;

-- E9 q3_seller_monthly_revenue
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('month', o.placed_at) AS month,
       count(DISTINCT o.order_id)        AS orders,
       sum(oi.quantity * oi.unit_price)  AS revenue
FROM konga.products p
JOIN konga.product_variants v ON v.product_id = p.product_id
JOIN konga.order_items oi     ON oi.variant_id = v.variant_id
JOIN konga.orders o           ON o.order_id = oi.order_id
WHERE p.seller_id = 42
  AND o.status = 'delivered'
GROUP BY 1
ORDER BY 1;

-- E9 q4_low_stock_in_category
EXPLAIN (ANALYZE, BUFFERS) SELECT p.product_id, p.name, v.sku, i.quantity_in_store
FROM konga.products p
JOIN konga.product_variants v ON v.product_id = p.product_id
JOIN konga.inventory i        ON i.variant_id = v.variant_id
WHERE p.category_id = 25
  AND p.status = 'live'
  AND i.quantity_in_store < 10
ORDER BY i.quantity_in_store, p.product_id;

-- E9 q5_product_name_search
EXPLAIN (ANALYZE, BUFFERS) SELECT product_id, name, status
FROM konga.products
WHERE name ILIKE '%laptop 1234%';

-- E9 q6_abandoned_pending_orders
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, customer_id, placed_at, total_amount
FROM konga.orders
WHERE status = 'pending'
  AND placed_at < now() - interval '2 days'
ORDER BY placed_at
LIMIT 50;

-- E9 q7_product_recent_reviews
EXPLAIN (ANALYZE, BUFFERS) SELECT review_id, customer_id, rating, comment, created_at
FROM konga.reviews
WHERE product_id = 777
ORDER BY created_at DESC
LIMIT 10;

-- E9 q8_top_customers_lifetime_value
EXPLAIN (ANALYZE, BUFFERS) SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value
FROM konga.customers c
JOIN konga.orders o ON o.customer_id = c.customer_id
WHERE o.status NOT IN ('cancelled','returned')
GROUP BY c.customer_id, c.full_name
ORDER BY lifetime_value DESC
LIMIT 10;

-- 
DROP SCHEMA IF EXISTS exp CASCADE;

-- 
CREATE SCHEMA exp;

-- E1 setup
CREATE TABLE exp.ostat AS SELECT order_id, customer_id, status, total_amount, placed_at FROM konga.orders;

-- 
ALTER TABLE exp.ostat SET (autovacuum_enabled = false);

-- 
CREATE INDEX ON exp.ostat (status);

-- 
ANALYZE exp.ostat;

-- A. fresh statistics ('pending' is a small share of rows)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'pending';

-- E1: data distribution changes (about 70% become 'pending'); statistics NOT refreshed
UPDATE exp.ostat SET status = 'pending' WHERE right(order_id, 12)::bigint % 10 < 7;

-- B. STALE statistics after the data changed
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'pending';

-- E1: refresh statistics
ANALYZE exp.ostat;

-- C. after ANALYZE (statistics refreshed)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'pending';

-- E2a IN (subquery)
EXPLAIN (ANALYZE, BUFFERS) SELECT customer_id, full_name FROM konga.customers WHERE customer_id IN (SELECT customer_id FROM konga.orders WHERE placed_at >= now() - interval '7 days');

-- E2a EXISTS (correlated)
EXPLAIN (ANALYZE, BUFFERS) SELECT c.customer_id, c.full_name FROM konga.customers c WHERE EXISTS (SELECT 1 FROM konga.orders o WHERE o.customer_id = c.customer_id AND o.placed_at >= now() - interval '7 days');

-- E2a JOIN + DISTINCT
EXPLAIN (ANALYZE, BUFFERS) SELECT DISTINCT c.customer_id, c.full_name FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.placed_at >= now() - interval '7 days';

-- E2b correlated subquery per row
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, (SELECT sum(i.quantity * i.unit_price) FROM konga.order_items i WHERE i.order_id = o.order_id) AS total FROM konga.orders o WHERE o.customer_id < '00000001-0000-4000-8000-000000003000';

-- E2b join + GROUP BY (rewritten)
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(i.quantity * i.unit_price) AS total FROM konga.orders o LEFT JOIN konga.order_items i ON i.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000003000' GROUP BY o.order_id;

-- E2c function on column: date_trunc('day', placed_at) = DATE
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM konga.orders WHERE date_trunc('day', placed_at) = date_trunc('day', now() - interval '30 days');

-- E2c range on the bare column (rewritten)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM konga.orders WHERE placed_at >= date_trunc('day', now() - interval '30 days') AND placed_at < date_trunc('day', now() - interval '29 days');

-- E3 selective (UUID customer suffix below 000000000300, about 1.5% of orders) / optimiser's choice
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000000300' GROUP BY o.order_id;

-- 
SET enable_nestloop = off;

-- 
SET enable_mergejoin = off;

-- E3 selective (UUID customer suffix below 000000000300, about 1.5% of orders) / force hash join
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000000300' GROUP BY o.order_id;

-- 
RESET enable_nestloop;

-- 
RESET enable_mergejoin;

-- 
SET enable_nestloop = off;

-- 
SET enable_hashjoin = off;

-- E3 selective (UUID customer suffix below 000000000300, about 1.5% of orders) / force merge join
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000000300' GROUP BY o.order_id;

-- 
RESET enable_nestloop;

-- 
RESET enable_hashjoin;

-- 
SET enable_hashjoin = off;

-- 
SET enable_mergejoin = off;

-- E3 selective (UUID customer suffix below 000000000300, about 1.5% of orders) / force nested loop
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000000300' GROUP BY o.order_id;

-- 
RESET enable_hashjoin;

-- 
RESET enable_mergejoin;

-- E3 broad (UUID customer suffix below 000000015000, about 75% of orders) / optimiser's choice
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000015000' GROUP BY o.order_id;

-- 
SET enable_nestloop = off;

-- 
SET enable_mergejoin = off;

-- E3 broad (UUID customer suffix below 000000015000, about 75% of orders) / force hash join
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000015000' GROUP BY o.order_id;

-- 
RESET enable_nestloop;

-- 
RESET enable_mergejoin;

-- 
SET enable_nestloop = off;

-- 
SET enable_hashjoin = off;

-- E3 broad (UUID customer suffix below 000000015000, about 75% of orders) / force merge join
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000015000' GROUP BY o.order_id;

-- 
RESET enable_nestloop;

-- 
RESET enable_hashjoin;

-- 
SET enable_hashjoin = off;

-- 
SET enable_mergejoin = off;

-- E3 broad (UUID customer suffix below 000000015000, about 75% of orders) / force nested loop
EXPLAIN (ANALYZE, BUFFERS) SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000015000' GROUP BY o.order_id;

-- 
RESET enable_hashjoin;

-- 
RESET enable_mergejoin;

-- E4 setup
CREATE TABLE exp.p4 AS SELECT payment_id, order_id, method, status, amount, created_at FROM konga.payments;

-- 
ANALYZE exp.p4;

-- 
VACUUM ANALYZE exp.p4;

-- 1. no index (heap scan)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- 
CREATE INDEX i_single ON exp.p4 (method);

-- 
VACUUM ANALYZE exp.p4;

-- 2. single-column B-tree (method)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- 
DROP INDEX exp.i_single;

-- 
CREATE INDEX i_hash ON exp.p4 USING hash (method);

-- 
VACUUM ANALYZE exp.p4;

-- 3. hash index (method)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- 
DROP INDEX exp.i_hash;

-- 
CREATE INDEX i_multi ON exp.p4 (method, status, created_at DESC);

-- 
VACUUM ANALYZE exp.p4;

-- 4. multi-column B-tree (method, status, created_at DESC)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- 
DROP INDEX exp.i_multi;

-- 
CREATE INDEX i_cover ON exp.p4 (method, status, created_at DESC) INCLUDE (payment_id, amount);

-- 
VACUUM ANALYZE exp.p4;

-- 5. covering (same keys + INCLUDE payment_id, amount)
EXPLAIN (ANALYZE, BUFFERS) SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20;

-- Q8 on base tables (join + aggregate every time)
EXPLAIN (ANALYZE, BUFFERS) SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.status = 'delivered' GROUP BY c.customer_id, c.full_name ORDER BY lifetime_value DESC LIMIT 10;

-- E5 materialised view
CREATE MATERIALIZED VIEW exp.mv_customer_ltv AS SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.status = 'delivered' GROUP BY c.customer_id, c.full_name;

-- 
CREATE INDEX ON exp.mv_customer_ltv (lifetime_value DESC);

-- 
ANALYZE exp.mv_customer_ltv;

-- Q8 from the materialised view
EXPLAIN (ANALYZE, BUFFERS) SELECT customer_id, full_name, orders, lifetime_value FROM exp.mv_customer_ltv ORDER BY lifetime_value DESC LIMIT 10;

-- E5 refresh cost
REFRESH MATERIALIZED VIEW exp.mv_customer_ltv;

-- Seller x month revenue report on base tables
EXPLAIN (ANALYZE, BUFFERS) SELECT p.seller_id, date_trunc('month', o.placed_at) AS month, sum(oi.quantity * oi.unit_price) AS revenue FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id JOIN konga.product_variants v ON v.variant_id = oi.variant_id JOIN konga.products p ON p.product_id = v.product_id WHERE o.status = 'delivered' GROUP BY p.seller_id, date_trunc('month', o.placed_at) ORDER BY 1, 2 LIMIT 20;

-- E5 materialised view 2
CREATE MATERIALIZED VIEW exp.mv_seller_revenue AS SELECT p.seller_id, date_trunc('month', o.placed_at) AS month, sum(oi.quantity * oi.unit_price) AS revenue FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id JOIN konga.product_variants v ON v.variant_id = oi.variant_id JOIN konga.products p ON p.product_id = v.product_id WHERE o.status = 'delivered' GROUP BY p.seller_id, date_trunc('month', o.placed_at);

-- 
CREATE INDEX ON exp.mv_seller_revenue (seller_id, month);

-- 
ANALYZE exp.mv_seller_revenue;

-- Seller x month revenue from the materialised view
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.mv_seller_revenue ORDER BY seller_id, month LIMIT 20;

-- 
SET max_parallel_workers_per_gather = 0;

-- max_parallel_workers_per_gather = 0
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000;

-- 
SET max_parallel_workers_per_gather = 1;

-- max_parallel_workers_per_gather = 1
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000;

-- 
SET max_parallel_workers_per_gather = 2;

-- max_parallel_workers_per_gather = 2
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000;

-- 
SET max_parallel_workers_per_gather = 4;

-- max_parallel_workers_per_gather = 4
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000;

-- 
RESET max_parallel_workers_per_gather;

-- 
SET work_mem = '64kB';

-- 
SET max_parallel_workers_per_gather = 0;

-- ORDER BY over 150,000 rows, work_mem = 64kB
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC;

-- 
SET work_mem = '1MB';

-- 
SET max_parallel_workers_per_gather = 0;

-- ORDER BY over 150,000 rows, work_mem = 1MB
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC;

-- 
SET work_mem = '4MB';

-- 
SET max_parallel_workers_per_gather = 0;

-- ORDER BY over 150,000 rows, work_mem = 4MB
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC;

-- 
SET work_mem = '64MB';

-- 
SET max_parallel_workers_per_gather = 0;

-- ORDER BY over 150,000 rows, work_mem = 64MB
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC;

-- 
RESET work_mem;

-- 
RESET max_parallel_workers_per_gather;

-- E7 setup: physically sorted by order_id
CREATE TABLE exp.items_seq AS SELECT * FROM konga.order_items ORDER BY order_id;

-- E7 setup: random physical order (unordered heap)
CREATE TABLE exp.items_heap AS SELECT * FROM konga.order_items ORDER BY random();

-- 
ANALYZE exp.items_seq;

-- 
ANALYZE exp.items_heap;

-- 
ANALYZE exp.items_heap;

-- E7 Heap (unordered), no index / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_heap WHERE order_id = '00000008-0000-4000-8000-000000077777';

-- E7 Heap (unordered), no index / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_heap WHERE order_id BETWEEN '00000008-0000-4000-8000-000000070000' AND '00000008-0000-4000-8000-000000071500';

-- 
CREATE INDEX ih_btree ON exp.items_heap (order_id);

-- 
ANALYZE exp.items_heap;

-- E7 Heap + B-tree index (indexed organisation, scattered rows) / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_heap WHERE order_id = '00000008-0000-4000-8000-000000077777';

-- E7 Heap + B-tree index (indexed organisation, scattered rows) / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_heap WHERE order_id BETWEEN '00000008-0000-4000-8000-000000070000' AND '00000008-0000-4000-8000-000000071500';

-- 
DROP INDEX exp.ih_btree; CREATE INDEX ih_hash ON exp.items_heap USING hash (order_id);

-- 
ANALYZE exp.items_heap;

-- E7 Heap + hash index / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_heap WHERE order_id = '00000008-0000-4000-8000-000000077777';

-- E7 Heap + hash index / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_heap WHERE order_id BETWEEN '00000008-0000-4000-8000-000000070000' AND '00000008-0000-4000-8000-000000071500';

-- 
DROP INDEX exp.ih_hash;

-- 
CREATE INDEX ih_btree2 ON exp.items_heap (order_id);

-- E7: CLUSTER = physically sort the table by the index key (sequential / clustered organisation)
CLUSTER exp.items_heap USING ih_btree2;

-- 
ANALYZE exp.items_heap;

-- E7 Clustered on order_id + B-tree / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_heap WHERE order_id = '00000008-0000-4000-8000-000000077777';

-- E7 Clustered on order_id + B-tree / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_heap WHERE order_id BETWEEN '00000008-0000-4000-8000-000000070000' AND '00000008-0000-4000-8000-000000071500';

-- 
DROP INDEX exp.ih_btree2;

-- 
CREATE INDEX is_brin ON exp.items_seq USING brin (order_id);

-- 
ANALYZE exp.items_seq;

-- E7 Sorted table + BRIN index (block-range) / exact match
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exp.items_seq WHERE order_id = '00000008-0000-4000-8000-000000077777';

-- E7 Sorted table + BRIN index (block-range) / range (1,500 orders)
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(quantity) FROM exp.items_seq WHERE order_id BETWEEN '00000008-0000-4000-8000-000000070000' AND '00000008-0000-4000-8000-000000071500';

-- E9 q1_customer_order_history
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, placed_at, status, total_amount
FROM konga.orders
WHERE customer_id = '00000001-0000-4000-8000-000000001234'
ORDER BY placed_at DESC;

-- E9 q2_top_selling_90_days
EXPLAIN (ANALYZE, BUFFERS) SELECT oi.variant_id, v.sku, sum(oi.quantity) AS units_sold
FROM konga.orders o
JOIN konga.order_items oi ON oi.order_id = o.order_id
JOIN konga.product_variants v ON v.variant_id = oi.variant_id
WHERE o.placed_at >= now() - interval '90 days'
  AND o.status <> 'cancelled'
GROUP BY oi.variant_id, v.sku
ORDER BY units_sold DESC, oi.variant_id
LIMIT 10;

-- E9 q3_seller_monthly_revenue
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('month', o.placed_at) AS month,
       count(DISTINCT o.order_id)        AS orders,
       sum(oi.quantity * oi.unit_price)  AS revenue
FROM konga.products p
JOIN konga.product_variants v ON v.product_id = p.product_id
JOIN konga.order_items oi     ON oi.variant_id = v.variant_id
JOIN konga.orders o           ON o.order_id = oi.order_id
WHERE p.seller_id = '00000003-0000-4000-8000-000000000042'
  AND o.status = 'delivered'
GROUP BY 1
ORDER BY 1;

-- E9 q4_low_stock_in_category
EXPLAIN (ANALYZE, BUFFERS) SELECT p.product_id, p.name, v.sku, i.quantity_in_store
FROM konga.products p
JOIN konga.product_variants v ON v.product_id = p.product_id
JOIN konga.inventory i        ON i.variant_id = v.variant_id
WHERE p.category_id = '00000004-0000-4000-8000-000000000025'
  AND p.status = 'live'
  AND i.quantity_in_store < 10
ORDER BY i.quantity_in_store, p.product_id;

-- E9 q5_product_name_search
EXPLAIN (ANALYZE, BUFFERS) SELECT product_id, name, status
FROM konga.products
WHERE name ILIKE '%laptop 1234%';

-- E9 q6_abandoned_pending_orders
EXPLAIN (ANALYZE, BUFFERS) SELECT order_id, customer_id, placed_at, total_amount
FROM konga.orders
WHERE status = 'pending'
  AND placed_at < now() - interval '2 days'
ORDER BY placed_at
LIMIT 50;

-- E9 q7_product_recent_reviews
EXPLAIN (ANALYZE, BUFFERS) SELECT review_id, customer_id, rating, comment, created_at
FROM konga.reviews
WHERE product_id = '00000006-0000-4000-8000-000000000777'
ORDER BY created_at DESC
LIMIT 10;

-- E9 q8_top_customers_lifetime_value
EXPLAIN (ANALYZE, BUFFERS) SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value
FROM konga.customers c
JOIN konga.orders o ON o.customer_id = c.customer_id
WHERE o.status = 'delivered'
GROUP BY c.customer_id, c.full_name
ORDER BY lifetime_value DESC, c.customer_id
LIMIT 10;

