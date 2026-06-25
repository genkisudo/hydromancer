{{ config(materialized='table') }}

-- One row per trader: their first trade date within the loaded window.
-- "cohort_week" is used for retention bucketing in the mart.
SELECT
    trader,
    MIN(trade_date)                              AS first_trade_date,
    DATE_TRUNC('week', MIN(trade_date))          AS cohort_week,
    MIN(timestamp)                               AS first_trade_at
FROM {{ ref('stg_xyz_fills') }}
GROUP BY trader
