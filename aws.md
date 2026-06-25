### Context Summary for AI Coding Agent

I have AWS CLI installed, S3 bucket created on my AWS account. This document summarizes the AWS S3 environment, configurations, and edge cases resolved during the initial data pipeline setup. Use this context to script, automate, or troubleshoot the S3 synchronization process.

---

### 1. Environment Constants

* **AWS Account ID:** `400694392038`
* **Target S3 Bucket:** `s3://my-hyperliquid-xyz-reservoir`
* **Source S3 Bucket:** `s3://hydromancer-reservoir/by_dex/xyz/`
* **Source Region:** `ap-northeast-1`

---

### 2. S3 Pipeline Architecture & Constraints

The pipeline operates on an Extract-Load-Transform (ELT) architecture, pulling public Hyperliquid datasets (Fills, Candles, Snapshots, Orderbook) from a third-party source repository into a local target repository.

#### The Requester Pays Requirement

The source bucket (`s3://hydromancer-reservoir`) is configured as **Requester Pays**. All data transfer and access fees are billed to the local target AWS account (`400694392038`). Any API call or CLI command directed at the source bucket must explicitly include the requester-payer flag, or AWS will return a `403 Access Denied` error.

#### The Object Tagging Conflict

The source bucket allows public reading of objects but restricts access to object metadata and tags. Standard `aws s3 sync` commands default to copying object properties, which triggers an implicit `GetObjectTagging` call. This results in an `AccessDenied` error mid-transfer. The synchronization script must explicitly disable property copying.

---

### 3. Production-Ready CLI Command

To safely sync data from the source partition to the local target bucket without metadata crashes or billing rejections, execute the following command:

```bash
aws s3 sync s3://hydromancer-reservoir/by_dex/xyz/ s3://my-hyperliquid-xyz-reservoir/ \
  --request-payer requester \
  --region ap-northeast-1 \
  --copy-props none

```

* `--request-payer requester`: Authorizes the local account to pay for the data egress.
* `--copy-props none`: Bypasses the `GetObjectTagging` permission wall by copying only the raw data payloads.

---

### 4. Required IAM Permissions

The IAM identity (User, Group, or Role) executing the synchronization script requires an explicit identity-based policy. It must have read rights to the external source bucket and read/write rights to the local bucket.

Note the strict separation of bucket-level (`arn:aws:s3:::bucket`) and object-level (`arn:aws:s3:::bucket/*`) ARNs required by AWS IAM syntax.

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
        },
        {
            "Sid": "ReadWriteTargetBucket",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::my-hyperliquid-xyz-reservoir",
                "arn:aws:s3:::my-hyperliquid-xyz-reservoir/*"
            ]
        }
    ]
}

```

---

### 5. Automation Strategy for the Coding Agent

When writing the Prefect orchestration tasks or Python automation modules:

1. Wrap the execution using `boto3` or directly invoke the AWS CLI via a subprocess.
2. If utilizing `boto3` client calls directly instead of the CLI binary, ensure the `RequestPayer='requester'` parameter is passed to both the `list_objects_v2` and `copy_object` / `download_file` methods.
3. Leverage the sequential date-partitioned folder structure (`/date=YYYY-MM-DD/`) in your logic to dynamically sync specific days rather than listing the entire root directory sequentially.
