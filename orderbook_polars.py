import polars as pl
import boto3

# Resolve credentials from ~/.aws/credentials via boto3, then pass to Polars
session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()

S3_OPTS = {
    "aws_access_key_id": creds.access_key,
    "aws_secret_access_key": creds.secret_key,
    "aws_region": "ap-northeast-1",
    "aws_request_payer": "requester",
}

PATH = "s3://hydromancer-reservoir/by_dex/hyperliquid/orderbook/1m/perps/date=2026-04-06/BTC.parquet"

# Best bid / best ask / spread
df = pl.scan_parquet(
    PATH,
    storage_options=S3_OPTS,
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
    PATH,
    storage_options=S3_OPTS,
).select([
    pl.col("block_time_ms"),
    pl.col("bids"),
]).explode("bids").unnest("bids").collect()
# columns: block_time_ms, px, sz, n

print("=== best bid/ask/spread ===")
print(df.head(10))
print("\n=== exploded bids (long format) ===")
print(long.head(10))