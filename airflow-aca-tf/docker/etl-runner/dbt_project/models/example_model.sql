-- ============================================================
-- example_model.sql - Sample DBT model
-- Replace with your actual transformations
-- ============================================================

-- This is a simple example model
-- It will be materialized as a view in the staging schema

{{ config(
    materialized='view',
    schema='staging'
) }}

SELECT
    1 as id,
    'example' as name,
    GETDATE() as created_at

-- Replace this with your actual SQL transformations
-- Example:
-- SELECT
--     customer_id,
--     customer_name,
--     email,
--     created_at
-- FROM {{ source('raw', 'customers') }}
-- WHERE is_active = 1
