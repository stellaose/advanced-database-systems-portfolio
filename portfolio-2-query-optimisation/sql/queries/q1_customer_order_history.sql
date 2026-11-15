-- Q1: Show a customer’s orders, starting from recent.
SELECT order_id, placed_at, status, total_amount
FROM konga.orders
WHERE customer_id = '00000001-0000-4000-8000-000000001234'
ORDER BY placed_at DESC;
