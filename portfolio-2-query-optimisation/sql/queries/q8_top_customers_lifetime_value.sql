-- Q8: Top 10 customers by delivered-order value (analytics). Expected: a full scan is
-- unavoidable because every order is aggregated - indexes should not help much.
SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value
FROM konga.customers c
JOIN konga.orders o ON o.customer_id = c.customer_id
WHERE o.status = 'delivered'
GROUP BY c.customer_id, c.full_name
ORDER BY lifetime_value DESC, c.customer_id
LIMIT 10;
