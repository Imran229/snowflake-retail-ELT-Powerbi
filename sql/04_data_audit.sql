USE ROLE ACCOUNTADMIN;
USE WAREHOUSE learn_wh;
USE SCHEMA retail_db.raw;

SELECT 'orders: duplicate order_id' AS check_name, COUNT(*) - COUNT(DISTINCT order_id) AS issue_count FROM orders
UNION ALL SELECT 'customers: duplicate customer_id', COUNT(*) - COUNT(DISTINCT customer_id) FROM customers
UNION ALL SELECT 'products: duplicate product_id', COUNT(*) - COUNT(DISTINCT product_id) FROM products
UNION ALL SELECT 'order_items: duplicate order_item_id', COUNT(*) - COUNT(DISTINCT order_item_id) FROM order_items
UNION ALL SELECT 'orders: null customer_id', COUNT_IF(customer_id IS NULL) FROM orders
UNION ALL SELECT 'orders: null order_date', COUNT_IF(order_date IS NULL) FROM orders
UNION ALL SELECT 'orders: null promotion_id (info, normal ho sakta hai)', COUNT_IF(promotion_id IS NULL) FROM orders
UNION ALL SELECT 'orders: customer missing in customers', COUNT(*) FROM orders o LEFT JOIN customers c ON o.customer_id = c.customer_id WHERE c.customer_id IS NULL
UNION ALL SELECT 'orders: store missing in stores', COUNT(*) FROM orders o LEFT JOIN stores s ON o.store_id = s.store_id WHERE s.store_id IS NULL
UNION ALL SELECT 'orders: promotion missing in promotions', COUNT(*) FROM orders o LEFT JOIN promotions p ON o.promotion_id = p.promotion_id WHERE o.promotion_id IS NOT NULL AND p.promotion_id IS NULL
UNION ALL SELECT 'order_items: order missing in orders', COUNT(*) FROM order_items oi LEFT JOIN orders o ON oi.order_id = o.order_id WHERE o.order_id IS NULL
UNION ALL SELECT 'order_items: product missing in products', COUNT(*) FROM order_items oi LEFT JOIN products p ON oi.product_id = p.product_id WHERE p.product_id IS NULL
UNION ALL SELECT 'products: category missing in categories', COUNT(*) FROM products p LEFT JOIN categories c ON p.category_id = c.category_id WHERE c.category_id IS NULL
UNION ALL SELECT 'products: supplier missing in suppliers', COUNT(*) FROM products p LEFT JOIN suppliers s ON p.supplier_id = s.supplier_id WHERE s.supplier_id IS NULL
UNION ALL SELECT 'returns: order_item missing in order_items', COUNT(*) FROM returns r LEFT JOIN order_items oi ON r.order_item_id = oi.order_item_id WHERE oi.order_item_id IS NULL
UNION ALL SELECT 'payments: order missing in orders', COUNT(*) FROM payments p LEFT JOIN orders o ON p.order_id = o.order_id WHERE o.order_id IS NULL
UNION ALL SELECT 'shipments: order missing in orders', COUNT(*) FROM shipments s LEFT JOIN orders o ON s.order_id = o.order_id WHERE o.order_id IS NULL
UNION ALL SELECT 'orders with no payment', COUNT(*) FROM orders o LEFT JOIN payments p ON o.order_id = p.order_id WHERE p.payment_id IS NULL
UNION ALL SELECT 'orders with no shipment', COUNT(*) FROM orders o LEFT JOIN shipments s ON o.order_id = s.order_id WHERE s.shipment_id IS NULL
UNION ALL SELECT 'order_items: qty <= 0', COUNT_IF(qty <= 0) FROM order_items
UNION ALL SELECT 'order_items: price <= 0', COUNT_IF(price <= 0) FROM order_items
UNION ALL SELECT 'payments: amount <= 0', COUNT_IF(amount <= 0) FROM payments
UNION ALL SELECT 'orders placed before customer signup', COUNT(*) FROM orders o JOIN customers c ON o.customer_id = c.customer_id WHERE o.order_date < c.signup_date
UNION ALL SELECT 'returns: refund > item total', COUNT(*) FROM returns r JOIN order_items oi ON r.order_item_id = oi.order_item_id WHERE r.refund > oi.qty * oi.price
UNION ALL SELECT 'order_items: price differs from product list price (info)', COUNT(*) FROM order_items oi JOIN products p ON oi.product_id = p.product_id WHERE oi.price <> p.price;

SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE issue_count > 0;

-- Query B 
SELECT 'order_date range' AS metric, MIN(order_date)::STRING || ' to ' || MAX(order_date)::STRING AS value FROM orders
UNION ALL SELECT 'signup_date range', MIN(signup_date)::STRING || ' to ' || MAX(signup_date)::STRING FROM customers
UNION ALL SELECT 'promotion discount range', MIN(discount)::STRING || ' to ' || MAX(discount)::STRING FROM promotions
UNION ALL SELECT 'product price range', MIN(price)::STRING || ' to ' || MAX(price)::STRING FROM products
UNION ALL SELECT 'payment amount range', MIN(amount)::STRING || ' to ' || MAX(amount)::STRING FROM payments
UNION ALL SELECT 'shipment statuses', LISTAGG(DISTINCT status, ', ') FROM shipments
UNION ALL SELECT 'avg orders per customer', (COUNT(*) / COUNT(DISTINCT customer_id))::STRING FROM orders
UNION ALL SELECT 'avg items per order', (COUNT(*) / COUNT(DISTINCT order_id))::STRING FROM order_items;
-- quuery c 
WITH items AS (
  SELECT order_id, SUM(qty * price) AS items_total
  FROM order_items
  GROUP BY order_id
)
SELECT
  COUNT(*) AS orders_total,
  COUNT_IF(i.order_id IS NULL) AS orders_without_items,
  COUNT_IF(i.order_id IS NOT NULL AND p.amount = i.items_total) AS payment_equals_items,
  COUNT_IF(i.order_id IS NOT NULL AND p.amount < i.items_total) AS payment_less_than_items,
  COUNT_IF(i.order_id IS NOT NULL AND p.amount > i.items_total) AS payment_more_than_items
FROM orders o
JOIN payments p ON o.order_id = p.order_id
LEFT JOIN items i ON o.order_id = i.order_id;

-- query d 
SELECT p.promotion_id, p.discount, COUNT(*) AS orders_count
FROM orders o
JOIN promotions p ON o.promotion_id = p.promotion_id
GROUP BY p.promotion_id, p.discount
ORDER BY p.discount
LIMIT 15;

-- query e
SELECT YEAR(order_date) AS yr, COUNT(*) AS orders
FROM orders
GROUP BY yr
ORDER BY yr;