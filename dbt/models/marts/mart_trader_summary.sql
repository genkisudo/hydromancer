{{ config(materialized='table') }}

-- Lifetime stats per trader over the loaded window.
-- volume_percentile lets Metabase segment power users (top 1%, 10%, etc.)
SELECT
    d.trader,
    c.cohort_week,
    c.first_trade_date,
    COUNT(DISTINCT d.trade_date)                AS active_days,
    SUM(d.trade_count)                          AS total_trades,
    SUM(d.volume_usd)                           AS lifetime_volume_usd,
    SUM(d.realized_pnl)                         AS lifetime_pnl,
    SUM(d.fees_paid)                            AS lifetime_fees,
    SUM(d.liquidations)                         AS total_liquidations,
    SUM(d.taker_fills)                          AS total_taker_fills,
    SUM(d.maker_fills)                          AS total_maker_fills,
    AVG(d.avg_trade_size_usd)                   AS avg_trade_size_usd,
    NTILE(100) OVER (
        ORDER BY SUM(d.volume_usd)
    )                                           AS volume_percentile
FROM {{ ref('int_trader_daily') }} d
JOIN {{ ref('int_trader_cohorts') }} c USING (trader)
GROUP BY d.trader, c.cohort_week, c.first_trade_date
