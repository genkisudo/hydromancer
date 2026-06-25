{{
    config(
        materialized='incremental',
        unique_key=['trade_id', 'trader'],
        on_schema_change='sync_all_columns'
    )
}}

/*
  GRAIN: one row per (trade_id, trader). Every Hyperliquid trade is recorded
  from BOTH counterparties, so each trade_id appears twice (maker + taker).
  trade_id ALONE is NOT unique — using it as the incremental key would delete
  one side of every trade. This is also why SUM(volume_usd) across all rows
  double-counts market-wide volume; per-trader aggregates (our marts) are fine.
*/

/*
  Reads xyz perp fills from S3.
  hive_partitioning=true lets DuckDB prune to only the needed date directories —
  avoids opening files older than 30 days on the initial load.
  On incremental runs, only files newer than the last loaded timestamp are scanned.
*/
WITH raw AS (
    SELECT
        trade_id,
        tx_hash,
        address                             AS trader,
        coin,
        base_symbol,
        quote_symbol,
        side,
        direction,
        CAST(price AS DOUBLE)               AS price,
        CAST(size  AS DOUBLE)               AS size,
        CAST(price AS DOUBLE)
            * CAST(size AS DOUBLE)          AS volume_usd,
        CAST(realized_pnl AS DOUBLE)        AS realized_pnl,
        CAST(fee AS DOUBLE)                 AS fee,
        fee_token,
        CAST(start_position AS DOUBLE)      AS start_position,
        is_liquidation,
        liquidation_method,
        CAST(liquidation_mark_px AS DOUBLE) AS liquidation_mark_px,
        crossed,
        builder,
        timestamp,
        -- UTC calendar date of the fill, independent of session timezone.
        -- timezone('UTC', ts) yields the UTC wall-clock as a naive TIMESTAMP;
        -- casting that to DATE gives the true UTC day. Using DATE_TRUNC on the
        -- raw timestamptz instead would truncate in the session tz and misplace
        -- ~7% of rows around the day boundary.
        CAST(timezone('UTC', timestamp) AS DATE) AS trade_date,
        -- virtual hive-partition column (string '2026-06-24')
        "date"                              AS partition_date
    FROM {{ source('hydromancer', 'xyz_perp_fills') }}
    WHERE
        {% if is_incremental() %}
            -- only fetch new rows since last run
            timestamp > (SELECT MAX(timestamp) FROM {{ this }})
        {% else %}
            -- initial load: last 30 days only, using partition pruning
            CAST("date" AS DATE) >= CURRENT_DATE - INTERVAL 30 DAYS
        {% endif %}
)

SELECT * FROM raw
