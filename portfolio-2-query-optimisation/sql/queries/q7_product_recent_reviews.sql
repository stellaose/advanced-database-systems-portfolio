-- Q7: Latest 10 reviews on a product page.
SELECT review_id, customer_id, rating, comment, created_at
FROM konga.reviews
WHERE product_id = '00000006-0000-4000-8000-000000000777'
ORDER BY created_at DESC
LIMIT 10;
