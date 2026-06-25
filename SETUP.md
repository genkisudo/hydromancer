# Technical Support: Querying Hydromancer Reservoir with DuckDB

Step-by-step guide to query free Hyperliquid on-chain data (fills, candles,
snapshots, orderbook) directly from S3 using DuckDB — no data download required.

---

## Why you need an AWS account

The data is free and publicly accessible, but the bucket
`s3://hydromancer-reservoir` is configured as **Requester Pays**. AWS requires
every request to be signed by a valid account so it knows who to bill for the
S3 API costs (fractions of a cent per query). Without credentials, every request
returns `403 Access Denied` — even though the data itself is public.

You do **not** need your own S3 bucket. Just an account.

---

## Part 1 — Create an AWS account

1. Go to [https://aws.amazon.com](https://aws.amazon.com) and click **Create an
   AWS Account**.
2. Complete sign-up (requires a credit card; free tier is sufficient — typical
   query costs are under $0.01).
3. Sign in to the **AWS Management Console**.

---

## Part 2 — Create an IAM user with the right permissions

AWS best practice: never use your root account for programmatic access. Create
a dedicated IAM user.

1. In the AWS Console, search for **IAM** and open it.
2. Click **Users** → **Create user**.
3. Enter a username (e.g. `duckdb-hydromancer`) and click **Next**.
4. Select **Attach policies directly** → **Create policy**.
5. Choose the **JSON** tab and paste the following:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ReadSourceObjects",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            "Resource": "arn:aws:s3:::hydromancer-reservoir/*"
        },
        {
            "Sid": "ListSourceBucket",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::hydromancer-reservoir"
        }
    ]
}
```

6. Name the policy (e.g. `HydromancerReadOnly`) → **Create policy**.
7. Back on the user creation screen, search for and attach
   `HydromancerReadOnly` → **Next** → **Create user**.

> **IAM ARN syntax note:** `ListBucket` must target the bucket ARN *without*
> a trailing `/*`. `GetObject` must target it *with* `/*`. Mixing these up
> causes `AccessDenied` on listing even when object reads work.

---

## Part 3 — Generate Access Keys

1. Open the user you just created → **Security credentials** tab.
2. Scroll to **Access keys** → **Create access key**.
3. Select **Command Line Interface (CLI)** → tick the confirmation → **Next**.
4. Click **Create access key**.
5. **Copy both the Access Key ID and the Secret Access Key now** — the secret
   is shown only once.

---

## Part 4 — Install and configure the AWS CLI

The AWS CLI stores your credentials in `~/.aws/credentials`, which DuckDB reads
automatically.

**Install:**
```bash
# macOS
brew install awscli

# verify
aws --version
```

**Configure:**
```bash
aws configure
```

Enter when prompted:
```
AWS Access Key ID:     YOUR_ACCESS_KEY_ID
AWS Secret Access Key: YOUR_SECRET_ACCESS_KEY
Default region name:   ap-northeast-1
Default output format: json
```

> The default region here can be anything — DuckDB overrides it per-session.
> `ap-northeast-1` (Tokyo) is a sensible default since that's where the bucket
> lives.

**Verify credentials work:**
```bash
aws sts get-caller-identity
```

Expected output (values will differ):
```json
{
    "UserId": "AIDAV2SZ7GTTKXPNNH2I4",
    "Account": "400694392038",
    "Arn": "arn:aws:iam::400694392038:user/duckdb-hydromancer"
}
```

If this command returns an error, stop here and fix credentials before
proceeding.

---

## Part 5 — Install DuckDB

```bash
# macOS
brew install duckdb

# verify — need v0.10 or later; v1.5.x confirmed working
duckdb --version

# Python package (optional, for scripting)
pip install duckdb
```

---

## Part 6 — Run your first query

Launch the DuckDB interactive shell:

```bash
duckdb
```

Run these commands **in order** — all three blocks are required every new
session:

```sql
-- 1. Load the S3 extension
INSTALL httpfs;
LOAD httpfs;

-- 2. Authenticate using your ~/.aws/credentials
CREATE SECRET hydro (
    TYPE s3,
    PROVIDER credential_chain,
    REGION 'ap-northeast-1'
);

-- 3. Enable requester-pays (REQUIRED — the bucket will 403 without this)
SET s3_requester_pays = true;
```

Now query:

```sql
-- BTC fills for a single day, limit 10 rows as a smoke test
SELECT coin, side, price, size, timestamp
FROM read_parquet('s3://hydromancer-reservoir/by_dex/hyperliquid/fills/perp/all/date=2026-03-22/fills.parquet')
WHERE coin = 'BTC'
ORDER BY timestamp
LIMIT 10;
```

You should see rows of trade data within a few seconds.

---

## Part 7 — Python usage

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
con.execute("SET s3_requester_pays = true;")

df = con.execute("""
    SELECT coin, side, price, size, timestamp
    FROM read_parquet(
        's3://hydromancer-reservoir/by_dex/hyperliquid/fills/perp/all/date=2026-03-22/fills.parquet'
    )
    WHERE coin = 'BTC'
    ORDER BY timestamp
    LIMIT 10
""").fetchdf()

print(df)
```

---

## Part 8 — Persist setup across sessions (optional)

By default, `CREATE SECRET` and `SET` commands reset when you close DuckDB.
To auto-run them on every launch, create a startup file:

```bash
cat > ~/.duckdbrc << 'EOF'
INSTALL httpfs;
LOAD httpfs;
CREATE SECRET IF NOT EXISTS hydro (
    TYPE s3,
    PROVIDER credential_chain,
    REGION 'ap-northeast-1'
);
SET s3_requester_pays = true;
EOF
```

DuckDB reads `~/.duckdbrc` automatically on startup. After this, just open
`duckdb` and query immediately.

---

## Troubleshooting

### `Anonymous users cannot invoke requests against Requester Pays buckets`

DuckDB found no credentials at all. The `CREATE SECRET` step was skipped or
`~/.aws/credentials` is missing/empty. Run `aws sts get-caller-identity` to
confirm your credentials are configured.

### `Credentials are provided, but they did not work` (403)

Credentials were found but the requester-pays header is missing. You ran
`CREATE SECRET` but forgot `SET s3_requester_pays = true`. Run that line and
retry.

### `AccessDenied` on listing (wildcard queries hang or fail immediately)

Your IAM policy has a syntax error in the ARNs. Confirm:
- `ListBucket` → `arn:aws:s3:::hydromancer-reservoir` (no `/*`)
- `GetObject` → `arn:aws:s3:::hydromancer-reservoir/*` (with `/*`)

### `File not found` on a direct path

Liquidation, ADL, and TWAP files only exist for dates that had those events.
Use a wildcard (`date=*`) or check a date you know had activity.

### Wildcard query takes a long time to start

Expected. `date=*` across all dexes forces DuckDB to list every matching S3
prefix before reading. Test with a single dex and single date first, then
widen the range once you confirm it works.

---

## Cost reference

All costs billed to your AWS account. Typical ad-hoc exploration is
negligible.

| Operation | Cost |
|---|---|
| S3 GET request | ~$0.0004 per 1,000 requests |
| Data transfer out of Tokyo (to internet) | ~$0.11 per GB (`ap-northeast-1` rate; first 100 GB/month free) |
| Single-day BTC fills query | ~$0.001–0.002 total |
| Week-wide liquidations wildcard | ~$0.01–0.05 depending on data volume |

> Egress is billed at the **bucket's region rate** (Tokyo, ~$0.11/GB), not your
> location's rate. Running queries from compute inside `ap-northeast-1` avoids
> internet egress entirely.
