-- 03_rename_columns_uppercase.sql
-- Why: INFER_SCHEMA keeps CSV headers in lowercase, which Snowflake stores as
-- quoted identifiers (e.g. "order_id"). Unquoted queries look for ORDER_ID and fail
-- with "invalid identifier". This script renames every lowercase column to uppercase.
-- Safe to re-run: it only touches columns that are not already uppercase.
-- Run it after 02_load_raw.sql (and again if you re-create any raw table).

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE learn_wh;

EXECUTE IMMEDIATE $$
DECLARE
  c CURSOR FOR
    SELECT table_name, column_name
    FROM retail_db.information_schema.columns
    WHERE table_schema = 'RAW'
      AND column_name <> UPPER(column_name);
BEGIN
  FOR r IN c DO
    EXECUTE IMMEDIATE
      'ALTER TABLE retail_db.raw.' || r.table_name ||
      ' RENAME COLUMN "' || r.column_name || '" TO ' || UPPER(r.column_name);
  END FOR;
  RETURN 'done';
END;
$$;

-- Check: every column name should now be uppercase.
SELECT table_name, column_name
FROM retail_db.information_schema.columns
WHERE table_schema = 'RAW'
ORDER BY table_name, ordinal_position;
