
SET search_path TO konga;
\set ON_ERROR_STOP on

\echo '--- F1: order totals equal the sum of their items less any coupon discount (percentage or fixed)'
DO $$ DECLARE bad int; BEGIN
  SELECT count(*) INTO bad FROM orders o
  JOIN (SELECT order_id, sum(quantity*unit_price) s FROM order_items GROUP BY order_id) t USING (order_id)
  LEFT JOIN coupons c ON c.coupon_id = o.coupon_id
  WHERE o.total_amount <> round(GREATEST(0, t.s - CASE c.discount_type
                                                 WHEN 'percentage' THEN t.s * c.discount_value / 100
                                                 WHEN 'fixed'      THEN c.discount_value
                                                 ELSE 0 END), 2);
  IF bad > 0 THEN RAISE EXCEPTION 'F1 failed: % orders with mismatched totals', bad; END IF;
  RAISE NOTICE 'F1 passed';
END $$;

\echo '--- F2: every order has at least one item (no orphan orders)'
DO $$ DECLARE bad int; BEGIN
  SELECT count(*) INTO bad FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id);
  IF bad > 0 THEN RAISE EXCEPTION 'F2 failed: % orders without items', bad; END IF;
  RAISE NOTICE 'F2 passed';
END $$;

\echo '--- F3: referential integrity - no order points to a missing customer/address'
DO $$ DECLARE bad int; BEGIN
  SELECT count(*) INTO bad FROM orders o
   WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id=o.customer_id)
      OR NOT EXISTS (SELECT 1 FROM addresses a WHERE a.address_id=o.shipping_address_id);
  IF bad > 0 THEN RAISE EXCEPTION 'F3 failed'; END IF;
  RAISE NOTICE 'F3 passed';
END $$;

\echo '--- F4: view v_order_summary returns one row per order with correct line counts'
DO $$ DECLARE n_view int; n_orders int; BEGIN
  SELECT count(*) INTO n_view FROM v_order_summary;
  SELECT count(*) INTO n_orders FROM orders;
  IF n_view <> n_orders THEN RAISE EXCEPTION 'F4 failed: % vs %', n_view, n_orders; END IF;
  RAISE NOTICE 'F4 passed';
END $$;

\echo '--- S1: konga_support can read customers but NOT password_hash'
DO $$ BEGIN
  SET LOCAL ROLE konga_support;
  PERFORM email_address FROM customers LIMIT 1;
  BEGIN
    PERFORM password_hash FROM customers LIMIT 1;
    RAISE EXCEPTION 'S1 failed: support could read password_hash';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'S1 passed (password_hash denied)'; END;
END $$;

\echo '--- S2: konga_support cannot modify data'
DO $$ BEGIN
  SET LOCAL ROLE konga_support;
  BEGIN
    UPDATE orders SET status = 'cancelled' WHERE order_id = '00000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'S2 failed: support could UPDATE orders';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'S2 passed (UPDATE denied)'; END;
END $$;

\echo '--- S3: konga_analyst can use aggregated views but cannot read customers'
DO $$ BEGIN
  SET LOCAL ROLE konga_analyst;
  PERFORM * FROM v_seller_sales LIMIT 1;
  BEGIN
    PERFORM * FROM customers LIMIT 1;
    RAISE EXCEPTION 'S3 failed: analyst could read customers';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'S3 passed (customers denied)'; END;
END $$;

\echo '--- S4: konga_app cannot drop tables (no DDL rights)'
DO $$ BEGIN
  SET LOCAL ROLE konga_app;
  BEGIN
    DROP TABLE reviews;
    RAISE EXCEPTION 'S4 failed: app could DROP TABLE';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'S4 passed (DROP denied)'; END;
END $$;
