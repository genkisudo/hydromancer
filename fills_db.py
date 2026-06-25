import duckdb

con = duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("""
    CREATE SECRET hydro (
        TYPE s3,
        PROVIDER credential_chain,
        REGION 'ap-northeast-1'
    );
""")
con.execute("SET s3_requester_pays = true;")

df = con.execute("""
    SELECT * FROM read_parquet(
        's3://hydromancer-reservoir/by_dex/hyperliquid/fills/perp/all/date=2026-03-22/fills.parquet'
    )
    WHERE coin = 'BTC'
""").fetchdf()

print(df.head())