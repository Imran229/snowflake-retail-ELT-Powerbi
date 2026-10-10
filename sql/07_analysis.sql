USE ROLE ACCOUNTADMIN;
USE WAREHOUSE learn_wh;
USE SCHEMA retail_db.mart;


-- Q1: Monthly trend aur MoM growth (2024 ko hata diya)
WITH monthly AS (
  SELECT DATE_TRUNC('month', order_date) AS month,
         COUNT(*) AS orders,
         SUM(paid_amount) AS paid_revenue,
         ROUND(AVG(paid_amount), 2) AS aov
  FROM fact_order
  WHERE order_date < '2024-01-01'
  GROUP BY 1
)
SELECT month, orders, paid_revenue, aov,
       ROUND(100 * (paid_revenue - LAG(paid_revenue) OVER (ORDER BY month))
             / LAG(paid_revenue) OVER (ORDER BY month), 2) AS mom_growth_pct
FROM monthly
ORDER BY month;


-- Q2: Category performance (revenue share aur return rate)

SELECT p.category_name,
       SUM(f.gross_sales) AS gross_sales,
       ROUND(100 * RATIO_TO_REPORT(SUM(f.gross_sales)) OVER (), 2) AS share_pct,
       SUM(f.qty) AS units,
       ROUND(100 * COUNT_IF(f.is_returned) / COUNT(*), 2) AS return_rate_pct
FROM fact_order_item f
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY p.category_name
ORDER BY gross_sales DESC;

-- Q3: Har category ke top 3 products (QUALIFY practice)
SELECT p.category_name, f.product_id, SUM(f.gross_sales) AS gross_sales
FROM fact_order_item f
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY p.category_name, f.product_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY p.category_name ORDER BY SUM(f.gross_sales) DESC) <= 3
ORDER BY p.category_name, gross_sales DESC;
-- Q4: Top 10 stores aur revenue per employee
SELECT s.store_id, s.city, s.employee_count,
       COUNT(*) AS orders,
       SUM(o.paid_amount) AS paid_revenue,
       ROUND(SUM(o.paid_amount) / NULLIF(s.employee_count, 0), 0) AS revenue_per_employee
FROM fact_order o
JOIN dim_store s ON o.store_id = s.store_id
WHERE o.order_date < '2024-01-01'
GROUP BY s.store_id, s.city, s.employee_count
ORDER BY paid_revenue DESC
LIMIT 10;
-- Q5: Supplier country ke hisaab se sales aur returns
SELECT p.supplier_country,
       SUM(f.gross_sales) AS gross_sales,
       ROUND(100 * COUNT_IF(f.is_returned) / COUNT(*), 2) AS return_rate_pct
FROM fact_order_item f
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY p.supplier_country
ORDER BY gross_sales DESC;

-- Q6: Returns ka overall asar (raw vs capped refund)
SELECT COUNT(*) AS items,
       COUNT_IF(is_returned) AS returned_items,
       ROUND(100 * COUNT_IF(is_returned) / COUNT(*), 2) AS return_rate_pct,
       SUM(gross_sales) AS gross_sales,
       SUM(refund_raw) AS refund_raw,
       SUM(refund_capped) AS refund_capped,
       ROUND(100 * SUM(refund_capped) / SUM(gross_sales), 2) AS capped_refund_pct_of_sales
FROM fact_order_item;

-- Q7: Shipment status aur city-wise late rate

SELECT shipment_status, COUNT(*) AS orders,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 2) AS pct
FROM fact_order
GROUP BY shipment_status
ORDER BY orders DESC;

SELECT s.city, COUNT(*) AS orders,
       ROUND(100 * COUNT_IF(o.shipment_status = 'late') / COUNT(*), 2) AS late_pct
FROM fact_order o
JOIN dim_store s ON o.store_id = s.store_id
GROUP BY s.city
ORDER BY late_pct DESC;

-- Q8: Promotion discount buckets (bina-promo group exist nahi karta)
SELECT CASE WHEN discount < 15 THEN '1. Low (5-14)'
            WHEN discount < 25 THEN '2. Mid (15-24)'
            ELSE '3. High (25-39)' END AS discount_bucket,
       COUNT(*) AS orders,
       ROUND(AVG(paid_amount), 2) AS avg_paid,
       ROUND(AVG(gross_sales), 2) AS avg_items_total
FROM fact_order
GROUP BY 1
ORDER BY 1;

-- Q9: Customer concentration (top 10% customers ka revenue share)
WITH c AS (
  SELECT customer_id, SUM(paid_amount) AS rev
  FROM fact_order
  GROUP BY customer_id
), r AS (
  SELECT *, NTILE(10) OVER (ORDER BY rev DESC) AS decile
  FROM c
)
SELECT decile, COUNT(*) AS customers, SUM(rev) AS revenue,
       ROUND(100 * RATIO_TO_REPORT(SUM(rev)) OVER (), 2) AS share_pct
FROM r
GROUP BY decile
ORDER BY decile;


SELECT CASE WHEN discount < 15 THEN '1. Low'
            WHEN discount < 25 THEN '2. Mid'
            ELSE '3. High' END AS bucket,
       COUNT(*) AS promotions
FROM retail_db.staging.stg_promotions
GROUP BY 1 ORDER BY 1;


WITH p AS (
  SELECT product_id,
         SUM(CASE WHEN order_date <  '2022-01-01' THEN gross_sales ELSE 0 END) AS sales_2020_21,
         SUM(CASE WHEN order_date >= '2022-01-01' AND order_date < '2024-01-01' THEN gross_sales ELSE 0 END) AS sales_2022_23
  FROM retail_db.mart.fact_order_item
  GROUP BY product_id
)
SELECT COUNT(*) AS products,
       ROUND(CORR(sales_2020_21, sales_2022_23), 3) AS correlation
FROM p;
