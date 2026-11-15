-- Q1: A customer's order history (account page): newest first.
SELECT order_id, placed_at, status, total_amount
FROM konga.orders
WHERE customer_id = '00000001-0000-4000-8000-000000001234'
ORDER BY placed_at DESC;
