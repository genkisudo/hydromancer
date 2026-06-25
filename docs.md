# Fills

Every trade execution (fill) across all perpetual and spot markets on Hyperliquid and all HIP-3 dexes. Updated daily. Partitioned by date, split by dex and sub-dataset.

## S3 Paths

**Bucket:** `s3://hydromancer-reservoir` (requester pays)

```
global/fills/raw/date=YYYY-MM-DD/fills.parquet              All fills
global/fills/spot/all/date=YYYY-MM-DD/fills.parquet          Spot fills only
global/fills/spot/builder_fills/date=YYYY-MM-DD/fills.parquet

by_dex/{dex}/fills/perp/all/date=YYYY-MM-DD/fills.parquet
by_dex/{dex}/fills/perp/liquidations/date=YYYY-MM-DD/fills.parquet
by_dex/{dex}/fills/perp/adl/date=YYYY-MM-DD/fills.parquet
by_dex/{dex}/fills/perp/builder_fills/date=YYYY-MM-DD/fills.parquet
by_dex/{dex}/fills/perp/twap_fills/date=YYYY-MM-DD/fills.parquet
```

Sub-datasets (`liquidations`, `adl`, `builder_fills`, `twap_fills`) are subsets of `all`. A liquidation fill appears in both `liquidations/` and `all/`. Files are only created when non-empty — if a day has no ADL events for a dex, there is no `adl/` file for that date.

**Available dexes:** `hyperliquid`, `xyz`, `cash`, `hyna`, `flx`, `km`, `vntl`

## Schema

All fill files use the same 27-column Parquet schema:

| Column                | Type               | Description                                                                                                          |
| --------------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `coin`                | string             | Raw market identifier (e.g., `BTC`, `xyz:MSFT`, `@107`)                                                              |
| `dex`                 | string             | DEX name                                                                                                             |
| `asset_class`         | string             | `perp` or `spot`                                                                                                     |
| `base_symbol`         | string             | Base asset (e.g., `BTC`, `MSFT`, `PURR`)                                                                             |
| `quote_symbol`        | string             | Quote/collateral asset (e.g., `USDC`, `USDT0`, `USDE`, `USDH`)                                                       |
| `price`               | decimal(20,10)     | Execution price                                                                                                      |
| `size`                | decimal(20,10)     | Fill size                                                                                                            |
| `side`                | string             | `buy` or `sell`                                                                                                      |
| `timestamp`           | timestamp(ms, UTC) | Execution time                                                                                                       |
| `direction`           | string             | Position direction (see below)                                                                                       |
| `realized_pnl`        | decimal(20,10)     | Realized profit/loss from this fill                                                                                  |
| `tx_hash`             | string             | Transaction hash                                                                                                     |
| `order_id`            | uint64             | Order ID                                                                                                             |
| `trade_id`            | uint64             | Trade ID                                                                                                             |
| `fee`                 | decimal(20,10)     | Trading fee                                                                                                          |
| `fee_token`           | string             | Token used for fee payment                                                                                           |
| `address`             | string             | User wallet address                                                                                                  |
| `crossed`             | boolean            | Whether the order crossed the spread                                                                                 |
| `start_position`      | decimal(20,10)     | Position size before this fill                                                                                       |
| `client_order_id`     | string?            | Client-provided order ID (nullable)                                                                                  |
| `builder`             | string?            | Builder address (nullable)                                                                                           |
| `builder_fee`         | decimal(20,10)?    | Builder fee (nullable)                                                                                               |
| `deployer_fee`        | decimal(20,10)?    | Deployer fee (nullable, HIP-3 fills only). Column present from 2026-03-21 onwards; earlier files may not include it. |
| `priority_gas`        | decimal(20,10)?    | Priority gas fee in HYPE (nullable). Column present from 2026-04-13 onwards; earlier files may not include it.       |
| `twap_id`             | uint64?            | TWAP order ID (nullable)                                                                                             |
| `is_liquidation`      | boolean?           | `true` if user was liquidated, `null` for spot fills                                                                 |
| `liquidation_mark_px` | decimal(20,10)?    | Mark price at liquidation (nullable)                                                                                 |
| `liquidation_method`  | string?            | Liquidation method (nullable)                                                                                        |

### Direction values

**Perp positions:**

| Value          | Meaning                     |
| -------------- | --------------------------- |
| `Open Long`    | Opening a long position     |
| `Open Short`   | Opening a short position    |
| `Close Long`   | Closing a long position     |
| `Close Short`  | Closing a short position    |
| `Long > Short` | Flipping from long to short |
| `Short > Long` | Flipping from short to long |

**Liquidations:**

| Value                         | Meaning                           |
| ----------------------------- | --------------------------------- |
| `Liquidated Cross Long`       | Cross-margin long liquidation     |
| `Liquidated Cross Short`      | Cross-margin short liquidation    |
| `Liquidated Isolated Long`    | Isolated-margin long liquidation  |
| `Liquidated Isolated Short`   | Isolated-margin short liquidation |
| `Auto-Deleveraging`           | Auto-deleveraging event           |
| `Partial Borrow Liquidation`  | Partial borrow liquidation        |
| `Backstop Borrow Liquidation` | Backstop borrow liquidation       |

**Special:**

| Value              | Meaning                         |
| ------------------ | ------------------------------- |
| `Settlement`       | Settlement                      |
| `Net Child Vaults` | Net child vault position change |

**Spot:**

| Value                  | Meaning                |
| ---------------------- | ---------------------- |
| `Buy`                  | Spot buy               |
| `Sell`                 | Spot sell              |
| `Spot Dust Conversion` | Automatic dust cleanup |

## Quick Start

### DuckDB

```sql
-- Install and load httpfs extension for S3 access
INSTALL httpfs;
LOAD httpfs;
SET s3_region = 'ap-northeast-1';

-- All BTC fills on a specific day
SELECT * FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/fills/perp/all/date=2026-03-22/fills.parquet')
WHERE coin = 'BTC'
ORDER BY timestamp;

-- Daily volume by market
SELECT base_symbol, dex,
       sum(price * size) as volume_usd,
       count(*) as trades
FROM read_parquet('s3://hydromancer-reservoir/global/fills/raw/date=2026-03-22/fills.parquet')
WHERE asset_class = 'perp'
GROUP BY base_symbol, dex
ORDER BY volume_usd DESC;

-- All liquidations across all dexes for a week
SELECT *
FROM read_parquet('s3://hydromancer-reservoir/by_dex/*/fills/perp/liquidations/date=*/fills.parquet')
WHERE timestamp >= '2026-03-15' AND timestamp < '2026-03-22';

-- Spot trading activity
SELECT base_symbol, quote_symbol, count(*) as trades, sum(size) as total_size
FROM read_parquet('s3://hydromancer-reservoir/global/fills/spot/all/date=2026-03-22/fills.parquet')
GROUP BY base_symbol, quote_symbol
ORDER BY trades DESC;
```

### Python

```python
import duckdb

con = duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region = 'ap-northeast-1';")

df = con.execute("""
    SELECT * FROM read_parquet(
        's3://hydromancer-reservoir/by_dex/hyperliquid/fills/perp/all/date=2026-03-22/fills.parquet'
    )
    WHERE coin = 'BTC'
""").fetchdf()

print(df.head())
```


# Candles

1-second OHLCV candlestick data for every perpetual and spot market on Hyperliquid and all HIP-3 dexes. Updated daily. Larger intervals (1m, 5m, 1h, etc.) can be aggregated from the 1s data.

## S3 Paths

**Bucket:** `s3://hydromancer-reservoir` (requester pays)

```
global/candles/1s/date=YYYY-MM-DD/candles.parquet
by_dex/{dex}/candles/1s/date=YYYY-MM-DD/candles.parquet
```

Files are only created for dates with data. Each file contains all markets for that dex on that day.

## Schema

| Column         | Type               | Description                                             |
| -------------- | ------------------ | ------------------------------------------------------- |
| `coin`         | string             | Raw market identifier (e.g., `BTC`, `xyz:MSFT`, `@107`) |
| `dex`          | string             | DEX name                                                |
| `asset_class`  | string             | `perp` or `spot`                                        |
| `base_symbol`  | string             | Base asset (e.g., `BTC`, `MSFT`)                        |
| `quote_symbol` | string             | Quote/collateral asset (e.g., `USDC`, `USDT0`)          |
| `timestamp`    | timestamp(ms, UTC) | Candle open time                                        |
| `open`         | decimal(20,10)     | Open price                                              |
| `high`         | decimal(20,10)     | High price                                              |
| `low`          | decimal(20,10)     | Low price                                               |
| `close`        | decimal(20,10)     | Close price                                             |
| `volume`       | decimal(20,10)     | Volume in base asset                                    |
| `volume_quote` | decimal(20,10)     | Volume in quote asset                                   |
| `trade_count`  | uint32             | Number of trades                                        |

## Aggregating to Larger Intervals

Since we provide 1s candles, you can aggregate to any interval:

```sql
-- 1-minute candles from 1s data
SELECT
    coin,
    time_bucket(INTERVAL '1 minute', timestamp) as minute,
    first(open) as open,
    max(high) as high,
    min(low) as low,
    last(close) as close,
    sum(volume) as volume,
    sum(volume_quote) as volume_quote,
    sum(trade_count) as trade_count
FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/candles/1s/date=2026-03-22/candles.parquet')
WHERE coin = 'BTC'
GROUP BY coin, minute
ORDER BY minute;

-- 1-hour candles
SELECT
    coin,
    time_bucket(INTERVAL '1 hour', timestamp) as hour,
    first(open) as open,
    max(high) as high,
    min(low) as low,
    last(close) as close,
    sum(volume) as volume,
    sum(volume_quote) as volume_quote,
    sum(trade_count) as trade_count
FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/candles/1s/date=2026-03-22/candles.parquet')
WHERE coin = 'ETH'
GROUP BY coin, hour
ORDER BY hour;
```

## Quick Start

### DuckDB

```sql
INSTALL httpfs;
LOAD httpfs;
SET s3_region = 'ap-northeast-1';

-- BTC 1s candles for a day
SELECT timestamp, open, high, low, close, volume, trade_count
FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/candles/1s/date=2026-03-22/candles.parquet')
WHERE coin = 'BTC'
ORDER BY timestamp;

-- Most traded markets by quote volume
SELECT base_symbol, dex, sum(volume_quote) as total_volume
FROM read_parquet('s3://hydromancer-reservoir/global/candles/1s/date=2026-03-22/candles.parquet')
GROUP BY base_symbol, dex
ORDER BY total_volume DESC
LIMIT 20;

-- Multi-day query
SELECT *
FROM read_parquet('s3://hydromancer-reservoir/by_dex/xyz/candles/1s/date=*/candles.parquet')
WHERE coin = 'xyz:MSFT'
  AND timestamp >= '2026-03-20' AND timestamp < '2026-03-23';
```


# Snapshots

Daily snapshots of all trader positions, spot token balances, and account values. Taken from the on-chain ABCI state at end of day. Available from August 2025 onward.

{% hint style="info" %}
Some dates may be missing if the ABCI state file was not available. This is normal — check the S3 listing for available dates. The gap from late October to mid-December 2025 is a known period without ABCI state captures.
{% endhint %}

## S3 Paths

**Bucket:** `s3://hydromancer-reservoir` (requester pays)

```
global/snapshots/perp/all/date=YYYY-MM-DD/{block}_{timestamp}.parquet
global/snapshots/spot/date=YYYY-MM-DD/{block}_{timestamp}.parquet
global/snapshots/account_values/date=YYYY-MM-DD/{block}_{timestamp}.parquet

by_dex/{dex}/snapshots/perp/date=YYYY-MM-DD/{block}_{timestamp}.parquet
```

File names include the block number and timestamp (milliseconds) from the ABCI state, e.g., `926030000_1773706027926.parquet`.

## Perp Snapshot Schema

One row per user per market. Contains every open perpetual position.

| Column              | Type     | Description                                                                                                                                                                                                                                                                    |
| ------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `user`              | string   | Wallet address                                                                                                                                                                                                                                                                 |
| `market`            | string   | Market name (e.g., `BTC`, `xyz:MSFT`)                                                                                                                                                                                                                                          |
| `size`              | float64  | Position size (positive = long, negative = short)                                                                                                                                                                                                                              |
| `notional`          | float64  | Position notional value (USD)                                                                                                                                                                                                                                                  |
| `entry_price`       | float64  | Average entry price                                                                                                                                                                                                                                                            |
| `liquidation_price` | float64? | Estimated liquidation price (null if not calculable)                                                                                                                                                                                                                           |
| `leverage_type`     | string   | `cross` or `isolated`                                                                                                                                                                                                                                                          |
| `leverage`          | uint32   | Leverage multiplier                                                                                                                                                                                                                                                            |
| `funding_pnl`       | float64  | Cumulative funding PnL (USD)                                                                                                                                                                                                                                                   |
| `account_value`     | float64  | Margin available on the collateral token of the traded market. For Hyperliquid native markets this is the USDC margin. For HIP-3 dexes this is the margin in the dex's collateral token (e.g., USDE for HyENA, USDH for Felix). Includes spot collateral for unified accounts. |
| `account_mode`      | string?  | `standard`, `dex_abstraction`, `unified`, `portfolio_margin`                                                                                                                                                                                                                   |

## Spot Snapshot Schema

One row per user per token. Contains all spot token holdings with positive balance.

| Column        | Type    | Description                               |
| ------------- | ------- | ----------------------------------------- |
| `user`        | string  | Wallet address                            |
| `token`       | string  | Token name (e.g., `USDC`, `HYPE`, `PURR`) |
| `balance`     | float64 | Token balance                             |
| `entry_value` | float64 | Entry value in USD                        |

## Account Values Schema

One row per user per dex. Aggregated account-level metrics.

| Column                 | Type    | Description                                                                                                                                                                                                     |
| ---------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `user`                 | string  | Wallet address                                                                                                                                                                                                  |
| `dex`                  | string  | DEX name                                                                                                                                                                                                        |
| `collateral_token`     | string  | Collateral token (e.g., `USDC`, `USDE`)                                                                                                                                                                         |
| `account_value`        | float64 | Total margin available on the dex's collateral token. For Hyperliquid this is the USDC equity. For HIP-3 dexes this is the equity in the dex's collateral token. Includes spot collateral for unified accounts. |
| `total_long_notional`  | float64 | Sum of long position notionals                                                                                                                                                                                  |
| `total_short_notional` | float64 | Sum of short position notionals                                                                                                                                                                                 |
| `account_mode`         | string? | Account abstraction mode                                                                                                                                                                                        |

## Quick Start

### DuckDB

```sql
INSTALL httpfs;
LOAD httpfs;
SET s3_region = 'ap-northeast-1';

-- Top BTC positions by size on a specific day
SELECT user, size, notional, entry_price, liquidation_price, leverage_type, leverage
FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/snapshots/perp/date=2026-03-22/*.parquet')
WHERE market = 'BTC'
ORDER BY abs(size) DESC
LIMIT 20;

-- Open interest by market
SELECT market,
       sum(CASE WHEN size > 0 THEN notional ELSE 0 END) as long_notional,
       sum(CASE WHEN size < 0 THEN notional ELSE 0 END) as short_notional,
       count(*) as positions
FROM read_parquet('s3://hydromancer-reservoir/global/snapshots/perp/all/date=2026-03-22/*.parquet')
GROUP BY market
ORDER BY long_notional + abs(short_notional) DESC;

-- Largest accounts by value
SELECT user, dex, account_value, total_long_notional, total_short_notional
FROM read_parquet('s3://hydromancer-reservoir/global/snapshots/account_values/date=2026-03-22/*.parquet')
ORDER BY account_value DESC
LIMIT 20;

-- USDC whale balances
SELECT user, balance
FROM read_parquet('s3://hydromancer-reservoir/global/snapshots/spot/date=2026-03-22/*.parquet')
WHERE token = 'USDC'
ORDER BY balance DESC
LIMIT 20;
```


# Orderbook

20-level L2 orderbook snapshots for every perpetual and spot market on Hyperliquid and all HIP-3 dexes. Each snapshot captures the top 20 bid and ask price levels at the time it was taken — price, total size at the level, and order count. Updated weekly.

**Bucket:** `s3://hydromancer-reservoir` (requester pays)

```
by_dex/{dex}/orderbook/1m/{asset_class}/date=YYYY-MM-DD/{coin}.parquet
```

One file per coin per day. `{dex}` is `hyperliquid` for native perps/spot, or the HIP-3 dex name (`xyz`, `hyna`, `felix`, …). `{asset_class}` is `perps` . Files are only created for dates with data.

Coin naming:

* **Perps (native):** `BTC`, `ETH`, `SOL`, …
* **Perps (HIP-3):** same as the coin (e.g. `NVDA`, `AAPL`, `SP500`). Routed via the `{dex}` path segment.
* **Spot (native):** `@{pair_index}` (e.g. `@107`, `@142`). The legacy `PURR/USDC` pair has its slash URL-encoded as `PURR%2FUSDC.parquet` on disk.

## Schema

Each row is one complete orderbook snapshot. Bid and ask levels are stored as list columns (best price first), with up to 20 levels per side.

| Column          | Type                                           | Description                                                                                                                     |
| --------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `block_time_ms` | int64                                          | Block time in milliseconds since epoch (UTC)                                                                                    |
| `block_number`  | uint64                                         | Hyperliquid block number                                                                                                        |
| `bids`          | `list<struct<px:string, sz:string, n:uint32>>` | Bid levels, highest price first. `px` and `sz` are decimal strings for lossless precision; `n` is the order count at that level |
| `asks`          | `list<struct<px:string, sz:string, n:uint32>>` | Ask levels, lowest price first. Same field semantics as bids                                                                    |

**Why list-of-struct?** One row equals one complete snapshot, which matches how you'd think about the book. Parquet physically stores `bids.list.item.px`, `bids.list.item.sz`, and `bids.list.item.n` as separate columns under the hood — so column pruning still works. A query that only reads `bids[1].px` (the best bid over time) only loads that one physical column.

## Quick Start

### DuckDB

```sql
INSTALL httpfs;
LOAD httpfs;
SET s3_region = 'ap-northeast-1';

-- Best bid / best ask / spread / mid over the day
SELECT
    block_time_ms,
    CAST(bids[1].px AS DOUBLE) AS best_bid,
    CAST(asks[1].px AS DOUBLE) AS best_ask,
    CAST(asks[1].px AS DOUBLE) - CAST(bids[1].px AS DOUBLE) AS spread,
    (CAST(bids[1].px AS DOUBLE) + CAST(asks[1].px AS DOUBLE)) / 2 AS mid
FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/orderbook/1m/perps/date=2026-04-06/BTC.parquet')
ORDER BY block_time_ms;

-- Depth within 10 bps of mid (both sides, USD)
WITH snap AS (
    SELECT
        block_time_ms,
        (CAST(bids[1].px AS DOUBLE) + CAST(asks[1].px AS DOUBLE)) / 2 AS mid,
        bids, asks
    FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/orderbook/1m/perps/date=2026-04-06/BTC.parquet')
)
SELECT
    block_time_ms, mid,
    list_sum(list_transform(bids, b ->
        CASE WHEN CAST(b.px AS DOUBLE) >= mid * 0.999
             THEN CAST(b.sz AS DOUBLE) * CAST(b.px AS DOUBLE) ELSE 0 END
    )) AS bid_10bps_usd,
    list_sum(list_transform(asks, a ->
        CASE WHEN CAST(a.px AS DOUBLE) <= mid * 1.001
             THEN CAST(a.sz AS DOUBLE) * CAST(a.px AS DOUBLE) ELSE 0 END
    )) AS ask_10bps_usd
FROM snap
ORDER BY block_time_ms;

-- Multi-coin scan: average spread across the top native perps on a day
SELECT
    regexp_extract(filename, '/([^/]+)\.parquet$', 1) AS coin,
    AVG(CAST(asks[1].px AS DOUBLE) - CAST(bids[1].px AS DOUBLE)) AS avg_spread,
    AVG((CAST(bids[1].px AS DOUBLE) + CAST(asks[1].px AS DOUBLE)) / 2) AS avg_mid
FROM read_parquet(
    's3://hydromancer-reservoir/by_dex/hyperliquid/orderbook/1m/perps/date=2026-04-06/*.parquet',
    filename = true
)
GROUP BY coin
ORDER BY avg_mid DESC;

-- Multi-day query for a single coin
SELECT block_time_ms, bids[1].px AS best_bid, asks[1].px AS best_ask
FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/orderbook/1m/perps/date=*/BTC.parquet')
WHERE block_time_ms BETWEEN 1775347200000 AND 1775606400000
ORDER BY block_time_ms;
```

### Polars

```python
import polars as pl

# Best bid / best ask / spread
df = pl.scan_parquet(
    "s3://hydromancer-reservoir/by_dex/hyperliquid/orderbook/1m/perps/date=2026-04-06/BTC.parquet"
).select([
    pl.col("block_time_ms"),
    pl.col("bids").list.first().struct.field("px").cast(pl.Float64).alias("best_bid"),
    pl.col("asks").list.first().struct.field("px").cast(pl.Float64).alias("best_ask"),
]).with_columns(
    spread=pl.col("best_ask") - pl.col("best_bid"),
    mid=(pl.col("best_bid") + pl.col("best_ask")) / 2,
).collect()

# Explode to long format (one row per level) if you prefer
long = pl.scan_parquet(
    "s3://hydromancer-reservoir/by_dex/hyperliquid/orderbook/1m/perps/date=2026-04-06/BTC.parquet"
).select([
    pl.col("block_time_ms"),
    pl.col("bids"),
]).explode("bids").unnest("bids").collect()
# columns: block_time_ms, px, sz, n
```

## Notes

* **Time ordering.** Rows within each file are written in block order. You can iterate without sorting for streaming reconstructions.
* **Missing levels.** If a side of the book has fewer than 20 populated price levels, the list simply contains fewer elements — no padding with zero/null entries.
* **Dex prefixes.** The path's `{dex}` segment is the authoritative dex identifier. HIP-3 coin names do **not** include the `dex:` prefix here — e.g. a Trade\[XYZ] file for `NVDA` lives at `by_dex/xyz/orderbook/1m/perps/date=…/NVDA.parquet`.
* **Scale.** For context, a busy day for 602 markets produces \~866K rows total per day across all coins in the 1m cadence, roughly \~90 MB compressed.
