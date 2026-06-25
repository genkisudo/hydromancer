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
WHERE timestamp >= '2026-06-15' AND timestamp < '2026-06-22';

-- Spot trading activity
SELECT base_symbol, quote_symbol, count(*) as trades, sum(size) as total_size
FROM read_parquet('s3://hydromancer-reservoir/global/fills/spot/all/date=2026-03-22/fills.parquet')
GROUP BY base_symbol, quote_symbol
ORDER BY trades DESC;