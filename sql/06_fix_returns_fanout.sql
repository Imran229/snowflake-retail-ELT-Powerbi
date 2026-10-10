USE ROLE ACCOUNTADMIN;
USE WAREHOUSE learn_wh;
USE DATABASE retail_db;

-- 1) Returns ko ek row per order_item me badlo
CREATE OR REPLACE TABLE retail_db.staging.stg_returns_by_item AS
SELECT oi.order_item_id,
       COUNT(*)                              AS return_count,
       SUM(r.refund)                         AS refund_raw,
       oi.qty * oi.price                     AS line_total,
       LEAST(SUM(r.refund), oi.qty * oi.price) AS refund_capped,
       (SUM(r.refund) > oi.qty * oi.price)   AS refund_exceeds_line_total
FROM retail_db.raw.returns r
JOIN retail_db.raw.order_items oi ON r.order_item_id = oi.order_item_id
GROUP BY oi.order_item_id, oi.qty, oi.price;

-- 2) fact_order_item dobara banao
CREATE OR REPLACE TABLE retail_db.mart.fact_order_item AS
SELECT oi.order_item_id, oi.order_id, o.order_date, o.store_id, o.customer_id,
       oi.product_id, p.category_id, p.supplier_id,
       oi.qty, oi.price, oi.line_total AS gross_sales,
       COALESCE(r.return_count, 0)   AS return_count,
       COALESCE(r.refund_raw, 0)     AS refund_raw,
       COALESCE(r.refund_capped, 0)  AS refund_capped,
       (r.order_item_id IS NOT NULL) AS is_returned
FROM retail_db.staging.stg_order_items oi
JOIN retail_db.staging.stg_orders o ON oi.order_id = o.order_id
JOIN retail_db.mart.dim_product p ON oi.product_id = p.product_id
LEFT JOIN retail_db.staging.stg_returns_by_item r ON oi.order_item_id = r.order_item_id;
SELECT 'fact_order_item rows (expect 600000)' AS check_name, COUNT(*) AS n FROM retail_db.mart.fact_order_item
UNION ALL SELECT 'fact_order_item dup order_item_id (expect 0)', COUNT(*) - COUNT(DISTINCT order_item_id) FROM retail_db.mart.fact_order_item
UNION ALL SELECT 'sales diff fact vs staging (expect 0)',
  (SELECT SUM(gross_sales) FROM retail_db.mart.fact_order_item) - (SELECT SUM(line_total) FROM retail_db.staging.stg_order_items)
UNION ALL SELECT 'refund diff fact vs raw (expect 0)',
  (SELECT SUM(refund_raw) FROM retail_db.mart.fact_order_item) - (SELECT SUM(refund) FROM retail_db.raw.returns)
UNION ALL SELECT 'total return rows in fact (expect 30000)', (SELECT SUM(return_count) FROM retail_db.mart.fact_order_item)
UNION ALL SELECT 'stg_returns_by_item dup (expect 0)', COUNT(*) - COUNT(DISTINCT order_item_id) FROM retail_db.staging.stg_returns_by_item;