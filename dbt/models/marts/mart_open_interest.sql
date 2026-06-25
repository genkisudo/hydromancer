{{ config(materialized='table') }}

-- Daily open interest and leverage profile per market, from the latest
-- snapshot of each day. Grain: one row per (snapshot_date, market).
-- notional is treated as a magnitude (ABS); long/short split uses size sign.
SELECT
    snapshot_date,
    market,
    COUNT(*)                                           AS open_positions,
    COUNT(DISTINCT trader)                             AS traders,
    SUM(ABS(notional))                                 AS gross_oi_usd,
    SUM(ABS(notional)) FILTER (WHERE size > 0)         AS long_oi_usd,
    SUM(ABS(notional)) FILTER (WHERE size < 0)         AS short_oi_usd,
    AVG(leverage)                                      AS avg_leverage,
    MEDIAN(leverage)                                   AS median_leverage,
    MAX(leverage)                                      AS max_leverage,
    COUNT(*) FILTER (WHERE leverage_type = 'isolated') AS isolated_positions,
    COUNT(*) FILTER (WHERE leverage_type = 'cross')    AS cross_positions
FROM {{ ref('stg_xyz_positions') }}
GROUP BY snapshot_date, market
