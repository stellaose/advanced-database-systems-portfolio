-- E8 mixed read workload (Q1 account page 50%, Q7 product reviews 30%, Q5 name search 10%, Q6 abandoned orders 10%)
\set cid random(1, 20000)
\set pid random(1, 20000)
\set pick random(1, 10)
\if :pick <= 5
SELECT order_id, placed_at, status, total_amount FROM konga.orders WHERE customer_id = '00000001-0000-4000-8000-' || lpad(:cid::text, 12, '0') ORDER BY placed_at DESC;
\elif :pick <= 8
SELECT review_id, rating, created_at FROM konga.reviews WHERE product_id = '00000006-0000-4000-8000-' || lpad(:pid::text, 12, '0') ORDER BY created_at DESC LIMIT 10;
\elif :pick = 9
SELECT product_id, name FROM konga.products WHERE name ILIKE '%shirt ' || :pid || '%';
\else
SELECT order_id, placed_at FROM konga.orders WHERE status = 'pending' AND placed_at < now() - interval '2 days' ORDER BY placed_at LIMIT 50;
\endif
