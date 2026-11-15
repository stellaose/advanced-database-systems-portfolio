-- Q3: Monthly revenue for one seller (SellerHQ report), delivered orders only.
SELECT date_trunc('month', o.placed_at) AS month,
       count(DISTINCT o.order_id)        AS orders,
       sum(oi.quantity * oi.unit_price)  AS revenue
FROM konga.products p
JOIN konga.product_variants v ON v.product_id = p.product_id
JOIN konga.order_items oi     ON oi.variant_id = v.variant_id
JOIN konga.orders o           ON o.order_id = oi.order_id
WHERE p.seller_id = '00000003-0000-4000-8000-000000000042'
  AND o.status = 'delivered'
GROUP BY 1
ORDER BY 1;
