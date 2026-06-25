{{ config(materialized='table') }}

-- Week-over-week retention: for each cohort week, how many traders
-- returned in weeks 0, 1, 2, … since their first trade.
WITH cohorts AS (
    SELECT trader, cohort_week
    FROM {{ ref('int_trader_cohorts') }}
),
active_weeks AS (
    SELECT DISTINCT
        trader,
        DATE_TRUNC('week', trade_date) AS active_week
    FROM {{ ref('int_trader_daily') }}
)
SELECT
    c.cohort_week,
    a.active_week,
    DATEDIFF('week', c.cohort_week, a.active_week) AS weeks_since_first_trade,
    COUNT(DISTINCT a.trader)                        AS retained_traders,
    COUNT(DISTINCT c.trader)                        AS cohort_size,
    COUNT(DISTINCT a.trader) * 1.0
        / NULLIF(COUNT(DISTINCT c.trader), 0)       AS retention_rate
FROM cohorts c
LEFT JOIN active_weeks a USING (trader)
WHERE a.active_week >= c.cohort_week
GROUP BY c.cohort_week, a.active_week
ORDER BY c.cohort_week, a.active_week
