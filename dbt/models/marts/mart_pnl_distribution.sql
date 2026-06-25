{{ config(materialized='table') }}

-- PnL distribution: bucket traders into winner/loser/neutral tiers.
WITH trader_pnl AS (
    SELECT
        trader,
        SUM(realized_pnl) AS total_pnl,
        SUM(volume_usd)   AS total_volume
    FROM {{ ref('int_trader_daily') }}
    GROUP BY trader
)
SELECT
    CASE
        WHEN total_pnl >  1000 THEN 'Big winner   (>$1k)'
        WHEN total_pnl >   100 THEN 'Winner       ($100–$1k)'
        WHEN total_pnl >     0 THEN 'Small winner  ($0–$100)'
        WHEN total_pnl =     0 THEN 'Breakeven'
        WHEN total_pnl >  -100 THEN 'Small loser   ($0–-$100)'
        WHEN total_pnl > -1000 THEN 'Loser        (-$100–-$1k)'
        ELSE                        'Big loser    (<-$1k)'
    END                         AS pnl_bucket,
    COUNT(*)                    AS trader_count,
    SUM(total_volume)           AS bucket_volume_usd,
    AVG(total_pnl)              AS avg_pnl,
    MIN(total_pnl)              AS min_pnl,
    MAX(total_pnl)              AS max_pnl
FROM trader_pnl
GROUP BY pnl_bucket
ORDER BY AVG(total_pnl) DESC
