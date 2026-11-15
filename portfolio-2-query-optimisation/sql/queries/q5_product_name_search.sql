-- Q5: Catalogue search by part of the product name (case-insensitive).
SELECT product_id, name, status
FROM konga.products
WHERE name ILIKE '%laptop 1234%';
