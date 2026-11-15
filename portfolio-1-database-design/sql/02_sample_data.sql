SET LOCAL search_path TO konga;

INSERT INTO customers (customer_id, email_address, phone_number, full_name, password_hash, is_active, created_at) VALUES
 ('bceec3c5-c731-4fb2-a8f0-5066b1f987d9', 'ada.obi@example.com', '08011111111', 'Ada Obi', 'hash1', TRUE, '2026-10-31 09:00:00+01'),
 ('4cb025ea-36e9-4b9f-8c44-0475cf012951', 'tunde.bello@example.com', '08022222222', 'Tunde Bello', 'hash2', TRUE, '2026-10-31 09:00:00+01'),
 ('b5e50a05-94b8-4b5a-9c3c-1dfe6f16c3a1', 'chioma.eze@example.com', '08033333333', 'Chioma Eze', 'hash3', TRUE, '2026-10-31 09:00:00+01'),
 ('f337956a-40ef-496f-ae40-62bcaafab985', 'peter.paul@example.com', '08044444444', 'Peter Paul', 'hash4', TRUE, '2026-10-31 09:00:00+01');

INSERT INTO addresses (address_id, customer_id, line1, city, state, postal_code, is_default) VALUES
 ('3b91ba08-d10e-46c6-bd68-e2cdf722b92c', 'bceec3c5-c731-4fb2-a8f0-5066b1f987d9', '12 Allen Avenue', 'Ikeja', 'Lagos', '100271', TRUE),
 ('a69034f9-5dac-4987-b5d8-576114135d44', '4cb025ea-36e9-4b9f-8c44-0475cf012951', '5 Aminu Kano Cres', 'Wuse 2', 'FCT', '900288', TRUE),
 ('631503e3-8d01-453b-8dc1-a534e595f818', 'b5e50a05-94b8-4b5a-9c3c-1dfe6f16c3a1', '20 Aba Road', 'Port Harcourt', 'Rivers', '500001', TRUE);

INSERT INTO sellers (seller_id, business_name, email_address, status, commission_rate) VALUES
 ('fa80071d-93fa-4b83-9b38-b4cb3c183eff', 'TechHub Nigeria', 'sales@techhub.example.com', 'active', 8.00),
 ('581b5806-e2b7-4e5f-b84e-3a72256615c1', 'Naija Fashion Co', 'hello@naijafashion.example.com', 'active', 12.00);

INSERT INTO categories (category_id, parent_id, name, slug) VALUES
 ('b5f32a6b-508f-4318-83ad-74f5e0d3a20b', NULL, 'Phones & Tablets', 'phones-tablets'),
 ('c38d4f5f-9a3f-4011-a5fe-34ac8ffd5fba', NULL, 'Fashion', 'fashion');
INSERT INTO categories (category_id, parent_id, name, slug) VALUES
 ('f54d7aa5-14e2-489a-829e-59f83f46b1f2', 'b5f32a6b-508f-4318-83ad-74f5e0d3a20b', 'Smartphones', 'smartphones'),
 ('c4cab25f-7878-473e-ab35-14a15b2ac727', 'c38d4f5f-9a3f-4011-a5fe-34ac8ffd5fba', 'Men''s Clothing', 'mens-clothing');

INSERT INTO brands (brand_id, name) VALUES ('5fd41547-500a-46ca-9b5c-fb5ad8c8ea49', 'Samsung'), ('7ef65906-1c7e-4e63-8608-77a888127147', 'Tecno');

INSERT INTO products (product_id, seller_id, category_id, brand_id, name, description, status) VALUES
 ('5e6e4d11-ffae-4370-9416-e20ef50c5fc3', 'fa80071d-93fa-4b83-9b38-b4cb3c183eff', 'f54d7aa5-14e2-489a-829e-59f83f46b1f2', '5fd41547-500a-46ca-9b5c-fb5ad8c8ea49', 'Samsung Galaxy A15', 'Entry-level smartphone', 'live'),
 ('78f05980-d195-44a4-a1e5-724c13c2df0a', 'fa80071d-93fa-4b83-9b38-b4cb3c183eff', 'f54d7aa5-14e2-489a-829e-59f83f46b1f2', '7ef65906-1c7e-4e63-8608-77a888127147', 'Tecno Spark 20', 'Budget smartphone', 'live'),
 ('f280249b-9848-468d-ba50-6300852b271b', '581b5806-e2b7-4e5f-b84e-3a72256615c1', 'c4cab25f-7878-473e-ab35-14a15b2ac727', NULL, 'Ankara Shirt', 'Hand-made ankara shirt', 'live');

INSERT INTO product_variants (variant_id, product_id, sku, price) VALUES
 ('794c702a-beb4-4d9b-a4ce-e46393448c09', '5e6e4d11-ffae-4370-9416-e20ef50c5fc3', 'SAM-A15-128-BLK', 185000.00),
 ('4f8a7669-5d62-4219-b083-6b7f124df422', '5e6e4d11-ffae-4370-9416-e20ef50c5fc3', 'SAM-A15-128-BLU', 185000.00),
 ('dfbee643-4577-4e04-8b74-06770618c5f8', '78f05980-d195-44a4-a1e5-724c13c2df0a', 'TEC-SP20-256-GRN', 145000.00),
 ('2ad24f49-d621-4d7c-a124-ae758543e76a', 'f280249b-9848-468d-ba50-6300852b271b', 'ANK-SH-M-RED', 18500.00);

-- Inventory rows are created by the trigger; available_qty is generated.
UPDATE inventory SET quantity_in_store = 25 WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09';
UPDATE inventory SET quantity_in_store = 10 WHERE variant_id = '4f8a7669-5d62-4219-b083-6b7f124df422';
UPDATE inventory SET quantity_in_store = 1 WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8';
UPDATE inventory SET quantity_in_store = 60 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';

INSERT INTO carts (cart_id, customer_id, status) VALUES
 ('b591ae27-d2dc-4bc9-84ba-15c15f2ee510', 'bceec3c5-c731-4fb2-a8f0-5066b1f987d9', 'open'), ('2ae6298b-a1b3-4542-8fae-2039f7bca57b', '4cb025ea-36e9-4b9f-8c44-0475cf012951', 'checked_out');
INSERT INTO cart_items (cart_id, variant_id, quantity) VALUES
 ('b591ae27-d2dc-4bc9-84ba-15c15f2ee510', '794c702a-beb4-4d9b-a4ce-e46393448c09', 1), ('b591ae27-d2dc-4bc9-84ba-15c15f2ee510', '2ad24f49-d621-4d7c-a124-ae758543e76a', 2);

INSERT INTO coupons (coupon_id, code, discount_type, discount_value, valid_from, valid_to) VALUES
 ('ad169b28-31b9-4125-b239-6846b8144554', 'WELCOME10', 'percentage', 10.00, '2026-10-01 00:00:00+01', '2026-12-01 00:00:00+01');

-- Tunde's order: (185000 + 18500) less 10% = 183150.
INSERT INTO orders (order_id, customer_id, shipping_address_id, coupon_id, placed_at, status, total_amount) VALUES
 ('79273601-a9b1-4885-b6e7-a9c555f971cd', '4cb025ea-36e9-4b9f-8c44-0475cf012951', 'a69034f9-5dac-4987-b5d8-576114135d44', 'ad169b28-31b9-4125-b239-6846b8144554', '2026-11-10 09:00:00+01', 'delivered', 183150.00),
 ('38ab5d6f-cf77-40d1-8f19-e1f55b77d547', 'b5e50a05-94b8-4b5a-9c3c-1dfe6f16c3a1', '631503e3-8d01-453b-8dc1-a534e595f818', NULL, '2026-11-05 09:00:00+01', 'delivered', 145000.00);
INSERT INTO order_items (order_item_id, order_id, variant_id, quantity, unit_price) VALUES
 ('851eae03-00df-4862-8edc-aaf2ba5af786', '79273601-a9b1-4885-b6e7-a9c555f971cd', '794c702a-beb4-4d9b-a4ce-e46393448c09', 1, 185000.00),
 ('7a0d2100-c101-4bb9-a7d4-1fa0e85bb5b7', '79273601-a9b1-4885-b6e7-a9c555f971cd', '2ad24f49-d621-4d7c-a124-ae758543e76a', 1, 18500.00),
 ('8b1290ae-3577-4957-895b-baa7cee16d48', '38ab5d6f-cf77-40d1-8f19-e1f55b77d547', 'dfbee643-4577-4e04-8b74-06770618c5f8', 1, 145000.00);

INSERT INTO payments (payment_id, order_id, method, amount, status, provider_ref, paid_at) VALUES
 ('496f430e-a15f-4756-aa16-b7953ddcd2ef', '79273601-a9b1-4885-b6e7-a9c555f971cd', 'card', 183150.00, 'successful', 'KP-TEST-0001', '2026-11-10 09:05:00+01'),
 ('fad84de6-5203-4710-a97b-a26b7f062f75', '38ab5d6f-cf77-40d1-8f19-e1f55b77d547', 'wallet', 145000.00, 'successful', 'KP-TEST-0002', '2026-11-05 09:05:00+01');

INSERT INTO shipments (shipment_id, order_id, seller_id, fulfilled_by, status, tracking_number, shipped_at, delivered_at) VALUES
 ('6e988e4c-c5d2-47ab-b53a-8f27d45aed7f', '79273601-a9b1-4885-b6e7-a9c555f971cd', 'fa80071d-93fa-4b83-9b38-b4cb3c183eff', 'konga', 'delivered', 'KX0001', '2026-11-11 09:00:00+01', '2026-11-13 09:00:00+01'),
 ('03631229-178f-4c3c-84f4-abf3f7bf72ae', '79273601-a9b1-4885-b6e7-a9c555f971cd', '581b5806-e2b7-4e5f-b84e-3a72256615c1', 'seller', 'delivered', 'KX0002', '2026-11-11 09:00:00+01', '2026-11-12 09:00:00+01'),
 ('811979ee-08b5-4d89-9d60-090711c5ab36', '38ab5d6f-cf77-40d1-8f19-e1f55b77d547', 'fa80071d-93fa-4b83-9b38-b4cb3c183eff', 'konga', 'returned', 'KX0003', '2026-11-06 09:00:00+01', '2026-11-07 09:00:00+01');
INSERT INTO shipment_events (event_id, shipment_id, status, location, event_time) VALUES
 ('b37752bc-f11e-4bbe-855c-4d4a65216d9d', '6e988e4c-c5d2-47ab-b53a-8f27d45aed7f', 'picked_up', 'Lagos hub', '2026-11-11 09:00:00+01'),
 ('a15fc782-c52b-4860-9c09-6742da321197', '6e988e4c-c5d2-47ab-b53a-8f27d45aed7f', 'in_transit', 'Abuja hub', '2026-11-12 09:00:00+01'),
 ('5ca06453-b5b2-46d6-9112-88bfcc75222e', '6e988e4c-c5d2-47ab-b53a-8f27d45aed7f', 'delivered', 'Wuse 2', '2026-11-13 09:00:00+01');

INSERT INTO refunds (refund_id, payment_id, amount, reason, created_at) VALUES
 ('05785dde-683f-43f8-99ca-3fa50316e949', 'fad84de6-5203-4710-a97b-a26b7f062f75', 145000.00, 'Item returned: screen defect', '2026-11-10 09:00:00+01');

INSERT INTO reviews (review_id, customer_id, product_id, rating, comment) VALUES
 ('d31adcc1-fa59-436e-a5bc-7a14fb52ec56', '4cb025ea-36e9-4b9f-8c44-0475cf012951', '5e6e4d11-ffae-4370-9416-e20ef50c5fc3', 5, 'Fast delivery, phone works great'),
 ('95a14074-d8c1-4070-bedd-fd8a5a144922', '4cb025ea-36e9-4b9f-8c44-0475cf012951', 'f280249b-9848-468d-ba50-6300852b271b', 4, 'Nice fabric');

-- Historical October payout; net_amount is generated by the database.
INSERT INTO payouts (payout_id, seller_id, period_start, period_end, gross_sales, commission, status, paid_at) VALUES
 ('151ac1dd-9dac-41ab-84a5-f13d96d8960c', 'fa80071d-93fa-4b83-9b38-b4cb3c183eff', '2026-10-01', '2026-10-31', 185000.00, 14800.00, 'paid', '2026-11-01 09:00:00+01');

COMMIT;
