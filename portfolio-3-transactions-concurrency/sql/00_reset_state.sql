
SET search_path = konga;
UPDATE inventory SET quantity_in_store = 25, quantity_reserved = 0 WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09';
UPDATE inventory SET quantity_in_store = 10, quantity_reserved = 0 WHERE variant_id = '4f8a7669-5d62-4219-b083-6b7f124df422';
UPDATE inventory SET quantity_in_store = 1,  quantity_reserved = 0 WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8';  -- the "last unit"
UPDATE inventory SET quantity_in_store = 60, quantity_reserved = 0 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
UPDATE sellers   SET status = 'active' WHERE seller_id IN ('fa80071d-93fa-4b83-9b38-b4cb3c183eff', '581b5806-e2b7-4e5f-b84e-3a72256615c1');
DELETE FROM payments    WHERE order_id IN (SELECT order_id FROM orders WHERE total_amount = 1.00);
DELETE FROM order_items WHERE order_id IN (SELECT order_id FROM orders WHERE total_amount = 1.00);
DELETE FROM orders      WHERE total_amount = 1.00;  
