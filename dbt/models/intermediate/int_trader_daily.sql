{{ config(materialized='table') }}

SELECT
    trade_date,
    trader,
    base_symbol,
    COUNT(*)                                              AS trade_count,
    SUM(volume_usd)                                       AS volume_usd,
    SUM(realized_pnl)                                     AS realized_pnl,
    SUM(fee)                                              AS fees_paid,
    COUNT(*) FILTER (WHERE is_liquidation = true)         AS liquidations,
    COUNT(*) FILTER (WHERE side = 'buy')                  AS buys,
    COUNT(*) FILTER (WHERE side = 'sell')                 AS sells,
    AVG(volume_usd)                                       AS avg_trade_size_usd,
    COUNT(*) FILTER (WHERE crossed = true)                AS taker_fills,
    COUNT(*) FILTER (WHERE crossed = false)               AS maker_fills
FROM {{ ref('stg_xyz_fills') }}
GROUP BY trade_date, trader, base_symbol
