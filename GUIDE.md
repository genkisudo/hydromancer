# Querying Hydromancer Reservoir from DuckDB — Step-by-Step Guide

Free Hyperliquid trade data (fills, candles, snapshots, orderbook) lives in the
public S3 bucket `s3://hydromancer-reservoir`, stored as Parquet and queryable
directly with DuckDB — no download step required.

> **The one thing the official docs get wrong:** the bucket is **Requester
> Pays**. DuckDB needs `SET s3_requester_pays = true` *and* valid AWS
> credentials. Without the flag you get `403 Forbidden` even with good creds.
> The `docs.md` / `fills.sql` examples omit this and **will fail as written.**
> Every command below was tested against the live bucket on 2026-06-24.

---

## Verified environment

This guide was validated end-to-end on this machine:

| Component   | Version / value                                   |
| ----------- | ------------------------------------------------- |
| DuckDB CLI  | v1.5.4                                             |
| duckdb (py) | 1.5.2                                             |
| AWS CLI     | aws-cli/2.34.37                                    |
| AWS account | `400694392038` (user `s3-admin-user`) — creds OK  |
| Test query  | 2026-03-22 hyperliquid perp fills → **3,469,156 rows** |

If your `aws sts get-caller-identity` already returns an account, Step 1 is done.

---

## Step 1 — Confirm prerequisites

```bash
duckdb --version            # need v0.10+ ; v1.5.x verified
aws sts get-caller-identity # must print your Account/Arn, not an error
```

If DuckDB is missing: `brew install duckdb`
If AWS creds are missing: run `aws configure` (any default region is fine — we
set the bucket region per-session).

---

## Step 2 — Grant your IAM user read access to the source bucket

Attach this policy to your IAM identity (AWS Console → IAM → your user → Add
permissions → Create inline policy → JSON). Read-only; sufficient for querying:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ReadSourceObjects",
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:GetObjectVersion"],
            "Resource": "arn:aws:s3:::hydromancer-reservoir/*"
        },
        {
            "Sid": "ListSourceBucket",
            "Effect": "Allow",
            "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
            "Resource": "arn:aws:s3:::hydromancer-reservoir"
        }
    ]
}
```

> Note the deliberate split: `ListBucket` targets the bucket ARN **without** a
> trailing `/*`; `GetObject` targets the ARN **with** `/*`. Mixing these up is
> the most common cause of `AccessDenied`.

---

## Step 3 — Query from the DuckDB CLI

Launch `duckdb` and run:

```sql
INSTALL httpfs;
LOAD httpfs;

-- Pulls AWS creds from ~/.aws/credentials / env / SSO automatically
CREATE SECRET hydro (
    TYPE s3,
    PROVIDER credential_chain,
    REGION 'ap-northeast-1'
);

-- REQUIRED for this bucket — the piece missing from the official docs
SET s3_requester_pays = true;

-- All BTC fills on a specific day
SELECT coin, side, price, size, timestamp
FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/fills/perp/all/date=2026-03-22/fills.parquet')
WHERE coin = 'BTC'
ORDER BY timestamp
LIMIT 20;
```

**Alternative credential style** (if you don't want to use the AWS credential
chain — e.g. on a machine without `~/.aws/`):

```sql
SET s3_region = 'ap-northeast-1';
SET s3_access_key_id = 'YOUR_KEY';
SET s3_secret_access_key = 'YOUR_SECRET';
SET s3_requester_pays = true;
```

---

## Step 4 — Query from Python

```python
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
con.execute("SET s3_requester_pays = true;")   # <-- required

df = con.execute("""
    SELECT coin, side, price, size, timestamp
    FROM read_parquet(
        's3://hydromancer-reservoir/by_dex/hyperliquid/fills/perp/all/date=2026-03-22/fills.parquet'
    )
    WHERE coin = 'BTC'
    ORDER BY timestamp
    LIMIT 20
""").fetchdf()

print(df)
```

> This supersedes the bundled `fills_db.py`, which uses
> `SET s3_region` only and **403s** on this requester-pays bucket because it
> never sets `s3_requester_pays`.

---

## Step 5 — Explore the datasets

All paths are under `s3://hydromancer-reservoir`. Date partitions are
`date=YYYY-MM-DD`. Wildcards (`*`) work across dates and dexes.

| Dataset             | Path template                                                          |
| ------------------- | --------------------------------------------------------------------- |
| All fills (global)  | `global/fills/raw/date=.../fills.parquet`                             |
| Fills by dex        | `by_dex/{dex}/fills/perp/all/date=.../fills.parquet`                  |
| Liquidations        | `by_dex/{dex}/fills/perp/liquidations/date=.../fills.parquet`         |
| Spot fills          | `global/fills/spot/all/date=.../fills.parquet`                        |
| 1-second candles    | `by_dex/{dex}/candles/1s/date=.../candles.parquet`                    |
| Position snapshots  | `global/snapshots/perp/all/date=.../*.parquet`                        |
| Account values      | `global/snapshots/account_values/date=.../*.parquet`                 |
| Orderbook (L2, 20)  | `by_dex/{dex}/orderbook/1m/perps/date=.../{coin}.parquet`            |

**Available dexes:** `hyperliquid`, `xyz`, `cash`, `hyna`, `flx`, `km`, `vntl`

Example multi-day / multi-dex scan (liquidations for a week):

```sql
SELECT *
FROM read_parquet('s3://hydromancer-reservoir/by_dex/*/fills/perp/liquidations/date=*/fills.parquet')
WHERE timestamp >= '2026-03-15' AND timestamp < '2026-03-22';
```

See `docs.md` for the full 27-column fills schema, direction codes, and the
candles / snapshots / orderbook schemas.

---

## Cost & performance notes

- **You pay, not Hydromancer.** Requester Pays means GET requests and egress
  bill to account `400694392038`. Reads are cheap (~$0.0004 per 1,000 GETs;
  ~$0.09/GB egress out of `ap-northeast-1`), but a broad `date=*` wildcard over
  many dexes touches many files — scope your date ranges.
- **Push filters down.** Parquet column pruning + predicate pushdown mean
  `SELECT coin, price ... WHERE coin='BTC'` transfers far less than `SELECT *`.
- **Timestamps are UTC** (`timestamp(ms, UTC)`). The CLI/pandas may *display*
  them in your local zone (e.g. `+01:00`); the stored value is UTC.
- **Want zero per-query cost?** Sync the partitions you need into your own
  bucket once, then query that copy. See `aws.md` / `iam_policy.md` for the
  `aws s3 sync ... --request-payer requester --copy-props none` recipe.

---

## Troubleshooting

| Symptom                                              | Fix                                                                 |
| --------------------------------------------------- | ------------------------------------------------------------------- |
| `Anonymous users cannot invoke requests...`         | No creds reached DuckDB. Add the `CREATE SECRET` (or `SET s3_*`).   |
| `AccessDenied: Access Denied` (with creds present)  | Missing `SET s3_requester_pays = true`.                             |
| `403` on `ListObjects` / globbing                   | IAM `ListBucket` must target the bucket ARN **without** `/*`.       |
| `Unknown parameter 'requester_pays'` on `CREATE SECRET` | It's a session setting, not a secret option — use `SET s3_requester_pays = true`. |
| File not found for a date                           | Files exist only for dates with data; some snapshot dates are gaps. |
