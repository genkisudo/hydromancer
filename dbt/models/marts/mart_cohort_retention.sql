{{ config(materialized='table') }}

-- Week-over-week retention: for each cohort week, the share of that cohort's
-- traders who were active in each subsequent week.
WITH cohorts AS (
    SELECT trader, cohort_week
    FROM {{ ref('int_trader_cohorts') }}
),
cohort_sizes AS (
    -- Fixed denominator: total distinct traders in each cohort week.
    -- Must be computed independently of active_week, otherwise it collapses
    -- to the retained count and retention_rate is always 1.0.
    SELECT cohort_week, COUNT(DISTINCT trader) AS cohort_size
    FROM cohorts
    GROUP BY cohort_week
),
active_weeks AS (
    SELECT DISTINCT
        trader,
        DATE_TRUNC('week', trade_date) AS active_week
    FROM {{ ref('int_trader_daily') }}
),
retention AS (
    -- Distinct cohort traders active in each subsequent week.
    SELECT
        c.cohort_week,
        a.active_week,
        DATEDIFF('week', c.cohort_week, a.active_week) AS weeks_since_first_trade,
        COUNT(DISTINCT a.trader)                        AS retained_traders
    FROM cohorts c
    JOIN active_weeks a USING (trader)
    WHERE a.active_week >= c.cohort_week
    GROUP BY c.cohort_week, a.active_week
)
SELECT
    r.cohort_week,
    r.active_week,
    r.weeks_since_first_trade,
    r.retained_traders,
    s.cohort_size,
    r.retained_traders * 1.0
        / NULLIF(s.cohort_size, 0)                  AS retention_rate
FROM retention r
JOIN cohort_sizes s USING (cohort_week)
ORDER BY r.cohort_week, r.active_week
