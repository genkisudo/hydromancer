# Technical Support Guide: Ingesting Data from Requester Pays S3 Buckets

This article provides a step-by-step technical guide to configuring AWS IAM policies and AWS CLI commands to sync open-source datasets from external, public S3 buckets. Specifically, this covers architectures utilizing **Requester Pays** configurations, such as the Hydromancer reservoir for Hyperliquid data.

---

## Overview of the Architecture

Public datasets are often hosted in S3 buckets configured as **Requester Pays**. This means that while the data itself is free and publicly accessible, the hosting party does not pay for data transfer (egress) or API request costs. Instead, the AWS account downloading the data must authenticate itself and agree to cover these operational costs.

If your local IAM policies or CLI configurations are incorrect, AWS will default to a `403 Access Denied` error, masking the fact that the data is publicly available.

### Core Architecture Components

* **Source Bucket:** `s3://hydromancer-reservoir/by_dex/xyz/` (Region: `ap-northeast-1`)
* **Target Bucket:** `s3://my-hyperliquid-xyz-reservoir` (Account ID: `400694392038`)
* **Data Flow:** External Source Bucket $\rightarrow$ Local IAM Authenticated User/Role $\rightarrow$ Local Target S3 Bucket

---

## Step 1: Configure the Local IAM Policy

To pull data from an external Requester Pays bucket into your own bucket, your local IAM identity (User or Role) requires explicit identity-based permissions.

A common failure point is formatting the **Amazon Resource Names (ARNs)** incorrectly. AWS requires bucket-level permissions for listing operations and object-level permissions for downloading or uploading operations.

### Required IAM Policy JSON

Attach the following inline or managed policy to the IAM identity executing the sync pipeline. Replace the target bucket resource names if your environment names differ.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ReadExternalSourceObjects",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            "Resource": "arn:aws:s3:::hydromancer-reservoir/*"
        },
        {
            "Sid": "ListExternalSourceBucket",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::hydromancer-reservoir"
        },
        {
            "Sid": "WriteLocalTargetBucket",
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

### Syntax Breakdown

| Action | Target Resource | Purpose |
| --- | --- | --- |
| `s3:ListBucket` | `arn:aws:s3:::bucket-name` | Scans the directory structure to identify files. Requires the plain bucket ARN. |
| `s3:GetObject` | `arn:aws:s3:::bucket-name/*` | Downloads individual files. Requires the trailing wildcard (`/*`). |
| `s3:PutObject` | `arn:aws:s3:::bucket-name/*` | Writes files into your target bucket. Requires the trailing wildcard (`/*`). |

---

## Step 2: Execute the Sync Command via AWS CLI

Once the IAM permissions are applied, you must run the synchronization via the AWS CLI. Standard sync syntax will fail due to billing and metadata barriers. You must use specific flags to authorize the transfer costs and bypass security barriers on metadata.

### The Production-Ready Command

Execute the following command in your terminal or orchestration script:

```bash
aws s3 sync s3://hydromancer-reservoir/by_dex/xyz/ s3://my-hyperliquid-xyz-reservoir/ \
  --request-payer requester \
  --region ap-northeast-1 \
  --copy-props none

```

---

## Troubleshooting Common Errors

### Error: AccessDenied when calling the ListObjectsV2 operation

* **Cause:** The command is missing authorization for billing, or the source IAM statement lacks the plain bucket ARN.
* **Resolution:** Ensure the `--request-payer requester` flag is explicitly appended to the end of your command. Verify that the IAM policy lists `arn:aws:s3:::hydromancer-reservoir` exactly, without a trailing slash.

### Error: AccessDenied when calling the GetObjectTagging operation

* **Cause:** By default, AWS CLI version 2 tries to copy hidden metadata and tags from the source objects along with the raw files. While the public has read access to the files, they do not have permission to read the bucket's internal tagging policies.
* **Resolution:** Append the `--copy-props none` flag. This instructs the AWS CLI to ignore the metadata layer and download only the raw Parquet datasets, allowing the transfer to complete successfully.

### Performance Tip: Processing New Partitions

The `aws s3 sync` command naturally compares the source and target buckets. If a transfer is interrupted or if new daily data drops into the source, running this exact command again will skip files you already possess and download only the newly added files.