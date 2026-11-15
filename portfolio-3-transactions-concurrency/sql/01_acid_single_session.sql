
\set ON_ERROR_STOP off
\pset pager off
SET search_path = konga;
\ir 00_reset_state.sql
\echo '=== A1. ATOMICITY: checkout that fails halfway is rolled back completely ==='
\echo 'Before:'
SELECT variant_id, quantity_in_store, quantity_reserved FROM inventory WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
SELECT count(*) AS test_orders FROM orders WHERE total_amount = 1.00;
BEGIN;
INSERT INTO orders (customer_id, shipping_address_id, status, total_amount) VALUES ('bceec3c5-c731-4fb2-a8f0-5066b1f987d9', '3b91ba08-d10e-46c6-bd68-e2cdf722b92c', 'pending', 1.00);
INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
  SELECT max(order_id), '2ad24f49-d621-4d7c-a124-ae758543e76a', 2, 18500 FROM orders WHERE total_amount = 1.00;
UPDATE inventory SET quantity_reserved = quantity_reserved + 2 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
\echo 'Inside the transaction (changes visible only to this session):'
SELECT count(*) AS test_orders FROM orders WHERE total_amount = 1.00;
\echo 'Step 4 fails: payment amount must be > 0 (chk_payments_amount)'
INSERT INTO payments (order_id, method, amount) SELECT max(order_id), 'card', 0 FROM orders WHERE total_amount = 1.00;
\echo 'The transaction is now in an aborted state; any further statement is refused:'
SELECT 1;
ROLLBACK;
\echo 'After ROLLBACK: nothing from steps 1-3 survived.'
SELECT variant_id, quantity_in_store, quantity_reserved FROM inventory WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
SELECT count(*) AS test_orders FROM orders WHERE total_amount = 1.00;

\echo
\echo '=== A2. SAVEPOINT: undo only the failed part, keep the rest ==='
BEGIN;
INSERT INTO orders (customer_id, shipping_address_id, status, total_amount) VALUES ('bceec3c5-c731-4fb2-a8f0-5066b1f987d9', '3b91ba08-d10e-46c6-bd68-e2cdf722b92c', 'pending', 1.00);
SAVEPOINT before_payment;
INSERT INTO payments (order_id, method, amount) SELECT max(order_id), 'card', 0 FROM orders WHERE total_amount = 1.00;
ROLLBACK TO SAVEPOINT before_payment;
INSERT INTO payments (order_id, method, amount) SELECT max(order_id), 'pay_on_delivery', 1.00 FROM orders WHERE total_amount = 1.00;
COMMIT;
SELECT o.order_id, o.status, p.method, p.status AS pay_status FROM orders o JOIN payments p USING (order_id) WHERE o.total_amount = 1.00;

\echo
\echo '=== C. CONSISTENCY: a transaction that would break a rule is refused ==='
\echo 'Rule: reserved stock may never exceed stock on hand (chk_inventory_reserved).'
BEGIN;
UPDATE inventory SET quantity_reserved = 5 WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8';   -- on hand is 1
ROLLBACK;
SELECT variant_id, quantity_in_store, quantity_reserved FROM inventory WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8';

\echo
\echo '=== D-lite. COMMIT is permanent from the session point of view ==='
BEGIN;
UPDATE inventory SET quantity_in_store = quantity_in_store - 1 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
COMMIT;
SELECT variant_id, quantity_in_store FROM inventory WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
\ir 00_reset_state.sql
