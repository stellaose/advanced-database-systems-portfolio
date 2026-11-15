
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO konga;

CREATE FUNCTION pg_temp.expect_constraint(
    test_name TEXT, statement TEXT, expected_state TEXT, expected_constraint TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    actual_constraint TEXT;
    rejected BOOLEAN := FALSE;
BEGIN
    BEGIN
        EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS actual_constraint = CONSTRAINT_NAME;
        IF SQLSTATE <> expected_state OR actual_constraint IS DISTINCT FROM expected_constraint THEN
            RAISE EXCEPTION '%: unexpected error [%] constraint %: %',
                test_name, SQLSTATE, actual_constraint, SQLERRM;
        END IF;
        rejected := TRUE;
    END;
    IF NOT rejected THEN
        RAISE EXCEPTION 'FAIL %: invalid data was accepted', test_name;
    END IF;
    RAISE NOTICE 'PASS %', test_name;
END;
$$;

DO $$
DECLARE
    customer VARCHAR(36) := gen_random_uuid()::text;
    seller VARCHAR(36) := gen_random_uuid()::text;
    category VARCHAR(36) := gen_random_uuid()::text;
    product VARCHAR(36) := gen_random_uuid()::text;
    variation VARCHAR(36) := gen_random_uuid()::text;
    cart VARCHAR(36) := gen_random_uuid()::text;
    address VARCHAR(36) := gen_random_uuid()::text;
    purchase VARCHAR(36) := gen_random_uuid()::text;
    missing_customer VARCHAR(36) := gen_random_uuid()::text;
    email TEXT := customer || '@constraint-test.example';
    sku TEXT := 'TEST-' || variation;
BEGIN
    -- Create separate test records. The final ROLLBACK removes them.
    INSERT INTO customers (customer_id, email_address, phone_number, full_name, password_hash)
    VALUES (customer, email, left(customer, 20), 'Constraint Test', 'synthetic-test-hash');
    INSERT INTO sellers (seller_id, business_name, email_address)
    VALUES (seller, 'Constraint Test Seller', seller || '@constraint-test.example');
    INSERT INTO categories (category_id, name, slug) VALUES (category, 'Test category', category);
    INSERT INTO products (product_id, seller_id, category_id, name)
    VALUES (product, seller, category, 'Test product');
    INSERT INTO product_variants (variant_id, product_id, sku, price)
    VALUES (variation, product, sku, 100.00);
    UPDATE inventory SET quantity_in_store = 5 WHERE variant_id = variation;
    INSERT INTO addresses (address_id, customer_id, line1, city, state, is_default)
    VALUES (address, customer, 'Test street', 'Ikeja', 'Lagos', TRUE);
    INSERT INTO carts (cart_id, customer_id) VALUES (cart, customer);
    INSERT INTO orders (order_id, customer_id, shipping_address_id, total_amount)
    VALUES (purchase, customer, address, 100.00);

    PERFORM pg_temp.expect_constraint('T1: duplicate customer email',
        format('INSERT INTO customers (email_address, phone_number, full_name, password_hash) VALUES (%L, %L, %L, %L)',
               email, left(seller, 20), 'Duplicate email', 'test-hash'),
        '23505', 'customers_email_address_key');

    PERFORM pg_temp.expect_constraint('T2: negative product variation price',
        format('UPDATE product_variants SET price = -1 WHERE variant_id = %L', variation),
        '23514', 'product_variants_price_check');

    PERFORM pg_temp.expect_constraint('T3: address references a missing customer',
        format('INSERT INTO addresses (customer_id, line1, city, state) VALUES (%L, %L, %L, %L)',
               missing_customer, 'Test street', 'Ikeja', 'Lagos'),
        '23503', 'addresses_customer_id_fkey');

    PERFORM pg_temp.expect_constraint('T4: review rating above 5',
        format('INSERT INTO reviews (customer_id, product_id, rating) VALUES (%L, %L, 6)', customer, product),
        '23514', 'reviews_rating_check');

    PERFORM pg_temp.expect_constraint('T5: second default address',
        format('INSERT INTO addresses (customer_id, line1, city, state, is_default) VALUES (%L, %L, %L, %L, TRUE)',
               customer, 'Second street', 'Ikeja', 'Lagos'),
        '23505', 'uq_addresses_default');

    PERFORM pg_temp.expect_constraint('T6: reserved stock exceeds stock on hand',
        format('UPDATE inventory SET quantity_reserved = 6 WHERE variant_id = %L', variation),
        '23514', 'inventory_check');

    PERFORM pg_temp.expect_constraint('T7: zero cart item quantity',
        format('INSERT INTO cart_items (cart_id, variant_id, quantity) VALUES (%L, %L, 0)', cart, variation),
        '23514', 'cart_items_quantity_check');

    PERFORM pg_temp.expect_constraint('T8: duplicate SKU',
        format('INSERT INTO product_variants (product_id, sku, price) VALUES (%L, %L, 100)', product, sku),
        '23505', 'product_variants_sku_key');

    PERFORM pg_temp.expect_constraint('T9: second open cart',
        format('INSERT INTO carts (customer_id, status) VALUES (%L, %L)', customer, 'open'),
        '23505', 'uq_carts_open');

    PERFORM pg_temp.expect_constraint('T10: successful payment without payment date',
        format('INSERT INTO payments (order_id, method, status, amount) VALUES (%L, %L, %L, 100)',
               purchase, 'card', 'successful'),
        '23514', 'payments_check');

    PERFORM pg_temp.expect_constraint('T11: deleting a seller with a product',
        format('DELETE FROM sellers WHERE seller_id = %L', seller),
        '23503', 'products_seller_id_fkey');

    PERFORM pg_temp.expect_constraint('T12: percentage discount above 100',
        format('INSERT INTO coupons (code, discount_type, discount_value, valid_from, valid_to) VALUES (%L, %L, 101, %L, %L)',
               left(category, 36), 'percentage', '2026-11-01 00:00:00+01', '2026-12-01 00:00:00+01'),
        '23514', 'coupons_check1');

    RAISE NOTICE 'All 12 constraint tests passed.';
END;
$$;
ROLLBACK;
