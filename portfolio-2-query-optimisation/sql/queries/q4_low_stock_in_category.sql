-- Q4: Live products in one category whose variants are low on stock (restock alert).
SELECT p.product_id, p.name, v.sku, i.quantity_in_store
FROM konga.products p
JOIN konga.product_variants v ON v.product_id = p.product_id
JOIN konga.inventory i        ON i.variant_id = v.variant_id
WHERE p.category_id = '00000004-0000-4000-8000-000000000025'
  AND p.status = 'live'
  AND i.quantity_in_store < 10
ORDER BY i.quantity_in_store, p.product_id;
