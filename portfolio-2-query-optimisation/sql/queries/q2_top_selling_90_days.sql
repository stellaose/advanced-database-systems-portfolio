-- Q2: Most units ordered in the last 90 days, excluding cancelled orders.
SELECT oi.variant_id, v.sku, sum(oi.quantity) AS units_sold
FROM konga.orders o
JOIN konga.order_items oi ON oi.order_id = o.order_id
JOIN konga.product_variants v ON v.variant_id = oi.variant_id
WHERE o.placed_at >= now() - interval '90 days'
  AND o.status <> 'cancelled'
GROUP BY oi.variant_id, v.sku
ORDER BY units_sold DESC, oi.variant_id
LIMIT 10;
