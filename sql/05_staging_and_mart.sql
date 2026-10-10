USE ROLE ACCOUNTADMIN;
USE WAREHOUSE learn_wh;
USE DATABASE retail_db;

-- ========== STAGING ==========
USE SCHEMA retail_db.staging;

CREATE OR REPLACE TABLE stg_orders AS
SELECT order_id, customer_id, store_id, order_date, promotion_id
FROM raw.orders;

CREATE OR REPLACE TABLE stg_order_items AS
SELECT order_item_id, order_id, product_id, qty, price, qty * price AS line_total
FROM raw.order_items;

CREATE OR REPLACE TABLE stg_returns AS
SELECT r.return_id, r.order_item_id,
       r.refund AS refund_raw,
       oi.qty * oi.price AS line_total,
       LEAST(r.refund, oi.qty * oi.price) AS refund_capped,
       (r.refund > oi.qty * oi.price) AS refund_exceeds_line_total
FROM raw.returns r
JOIN raw.order_items oi ON r.order_item_id = oi.order_item_id;

CREATE OR REPLACE TABLE stg_payments AS
SELECT payment_id, order_id, amount AS paid_amount FROM raw.payments;

CREATE OR REPLACE TABLE stg_shipments AS
SELECT shipment_id, order_id, LOWER(TRIM(status)) AS status FROM raw.shipments;

CREATE OR REPLACE TABLE stg_promotions AS
SELECT promotion_id, discount FROM raw.promotions;

CREATE OR REPLACE TABLE stg_customers  AS SELECT customer_id, city, signup_date FROM raw.customers;
CREATE OR REPLACE TABLE stg_products   AS SELECT product_id, category_id, supplier_id, price FROM raw.products;
CREATE OR REPLACE TABLE stg_categories AS SELECT category_id, category_name FROM raw.categories;
CREATE OR REPLACE TABLE stg_suppliers  AS SELECT supplier_id, country FROM raw.suppliers;
CREATE OR REPLACE TABLE stg_stores     AS SELECT store_id, city FROM raw.stores;
CREATE OR REPLACE TABLE stg_employees  AS SELECT employee_id, store_id, salary FROM raw.employees;

-- ========== MART ==========
USE SCHEMA retail_db.mart;

CREATE OR REPLACE TABLE dim_customer AS
SELECT customer_id, city, signup_date FROM staging.stg_customers;

CREATE OR REPLACE TABLE dim_product AS
SELECT p.product_id, p.price AS list_price,
       p.category_id, c.category_name,
       p.supplier_id, s.country AS supplier_country
FROM staging.stg_products p
JOIN staging.stg_categories c ON p.category_id = c.category_id
JOIN staging.stg_suppliers s ON p.supplier_id = s.supplier_id;

CREATE OR REPLACE TABLE dim_store AS
SELECT s.store_id, s.city,
       COUNT(e.employee_id) AS employee_count,
       SUM(e.salary) AS total_salary
FROM staging.stg_stores s
LEFT JOIN staging.stg_employees e ON s.store_id = e.store_id
GROUP BY s.store_id, s.city;

CREATE OR REPLACE TABLE fact_order_item AS
SELECT oi.order_item_id, oi.order_id, o.order_date, o.store_id, o.customer_id,
       oi.product_id, p.category_id, p.supplier_id,
       oi.qty, oi.price, oi.line_total AS gross_sales,
       COALESCE(r.refund_raw, 0)    AS refund_raw,
       COALESCE(r.refund_capped, 0) AS refund_capped,
       (r.return_id IS NOT NULL)    AS is_returned
FROM staging.stg_order_items oi
JOIN staging.stg_orders o ON oi.order_id = o.order_id
JOIN mart.dim_product p ON oi.product_id = p.product_id
LEFT JOIN staging.stg_returns r ON oi.order_item_id = r.order_item_id;

CREATE OR REPLACE TABLE fact_order AS
SELECT o.order_id, o.customer_id, o.store_id, o.order_date, o.promotion_id,
       pr.discount,
       pay.paid_amount,
       sh.status AS shipment_status,
       i.items_total AS gross_sales,
       COALESCE(i.item_count, 0) AS item_count,
       (i.order_id IS NOT NULL) AS has_items
FROM staging.stg_orders o
JOIN staging.stg_payments pay ON o.order_id = pay.order_id
JOIN staging.stg_shipments sh ON o.order_id = sh.order_id
JOIN staging.stg_promotions pr ON o.promotion_id = pr.promotion_id
LEFT JOIN (
  SELECT order_id, SUM(line_total) AS items_total, COUNT(*) AS item_count
  FROM staging.stg_order_items
  GROUP BY order_id
) i ON o.order_id = i.order_id;

SELECT 'dim_customer' AS tbl, COUNT(*) AS n FROM retail_db.mart.dim_customer
UNION ALL SELECT 'dim_product', COUNT(*) FROM retail_db.mart.dim_product
UNION ALL SELECT 'dim_store', COUNT(*) FROM retail_db.mart.dim_store
UNION ALL SELECT 'fact_order', COUNT(*) FROM retail_db.mart.fact_order
UNION ALL SELECT 'fact_order_item', COUNT(*) FROM retail_db.mart.fact_order_item
UNION ALL SELECT 'returns dup order_item_id (expect 0)', COUNT(*) - COUNT(DISTINCT order_item_id) FROM retail_db.staging.stg_returns
UNION ALL SELECT 'sales diff fact vs staging (expect 0)',
  (SELECT SUM(gross_sales) FROM retail_db.mart.fact_order_item) - (SELECT SUM(line_total) FROM retail_db.staging.stg_order_items);