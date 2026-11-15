-- Q6: Pending orders older than 2 days 
SELECT order_id, customer_id, placed_at, total_amount
FROM konga.orders
WHERE status = 'pending'
  AND placed_at < now() - interval '2 days'
ORDER BY placed_at
LIMIT 50;
