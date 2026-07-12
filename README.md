
<img width="1200" height="675" alt="aws dynamodb " src="https://github.com/user-attachments/assets/a54d3820-6c91-4c80-94b1-5f4537f76dd3" />

# Data Expiration Automation with DynamoDB TTL
## Project Overview

This project implements automated data lifecycle management using Amazon DynamoDB's Time-To-Live (TTL) feature, deployed entirely through Terraform, so time-sensitive data like session tokens and cache entries expires and cleans itself up with zero ongoing maintenance.

**Why this matters in the real world:** Every application with sessions, caches, or temporary records eventually needs a way to clean up stale data. Hand-built cleanup jobs (cron scripts, scheduled Lambdas scanning for old rows) add operational overhead and cost to run. TTL turns "delete this in X minutes" into a single attribute on the data itself. No infrastructure to run, no write capacity consumed. This exact pattern shows up across production systems handling session tokens, rate-limit counters, and cache entries in virtually every serverless architecture.

## Problem


Organizations often accumulate vast amounts of time-sensitive data in their databases that becomes less valuable over time, such as session data, temporary user preferences, or cache entries. Manually managing data retention policies creates operational overhead and can lead to storage bloat that increases costs and impacts query performance. Without automated cleanup mechanisms, databases grow indefinitely, leading to unnecessary storage expenses and degraded application performance.

## Solution

DynamoDB's Time-To-Live (TTL) feature provides an automated, cost-effective solution for data lifecycle management by allowing you to define expiration timestamps for individual items. The service automatically deletes expired items without consuming write capacity units, reducing both storage costs and operational overhead while maintaining optimal database performance through automated cleanup processes.

## Architecture Diagram

<img width="881" height="712" alt="image-2" src="https://github.com/user-attachments/assets/89c5012f-0685-4d25-8aaa-67bae8c9434d" />


**Breakdown of what is happening:**

1. **Application Layer** — the Application writes items into the table carrying a TTL attribute (`expires_at`), and separately reads back only the active (non-expired) items.
2. **Database Layer** — the DynamoDB Table with TTL Enabled stores all items, expired or not, until the background process catches up to them.
3. **TTL Process** — the TTL Background Process continuously scans the table looking for items whose TTL timestamp has passed.
4. **Automatic Deletion** — items flagged as expired by the scan are removed from the table, without consuming any write capacity units.
5. **Monitoring** — TTL activity is streamed to CloudWatch Metrics, giving visibility into how many items are being deleted over time.

## Prerequisites

- AWS account with permissions to manage DynamoDB tables and CloudWatch alarms
- Terraform >= 1.0, with the `hashicorp/aws` provider pinned to `~> 5.0`
- AWS CLI v2, configured with credentials

## Tools & Services Used


- Terraform (`hashicorp/aws` provider `~> 5.0`, `hashicorp/random` `~> 3.1`)
- Amazon DynamoDB (on-demand table with TTL enabled)
- Amazon CloudWatch (alarm on `TimeToLiveDeletedItemCount`, plus a log group)
- AWS CLI (invoked via a `local-exec` provisioner to seed sample data)

## Preparation


- **`versions.tf`** — pins the Terraform and provider versions (`aws`, `random`) and configures the AWS provider with `default_tags` applied to every resource
- **`variables.tf`** — every configurable input: region, environment, table naming, TTL attribute name, billing mode, encryption and point-in-time recovery toggles, and monitoring/sample-data flags, each with a `validation` block
- **`main.tf`** — the DynamoDB table itself with its `ttl` block, the CloudWatch alarm and log group, and a `null_resource` that seeds representative sample data via the AWS CLI
- **`outputs.tf`** — table identifiers, TTL/billing/encryption status, ready-to-run CLI validation commands, and a cost summary
- **`terraform.tfvars`** — real deployment values (region, owner, cost center), gitignored, with a sanitized `terraform.tfvars.example` committed in its place

## Steps


### **1. Create the DynamoDB Table with TTL Enabled:**

DynamoDB provides a fully managed NoSQL database service that scales automatically based on your application's needs. Creating a table with appropriate partition and sort keys establishes the foundation for storing time-sensitive data that will benefit from automated expiration. The on-demand billing mode ensures cost efficiency for variable workloads while providing consistent performance.

<img width="594" height="392" alt="image-3" src="https://github.com/user-attachments/assets/73ec596c-9c65-44de-b0c0-c588bd1a9759" />


Enabling TTL transforms your DynamoDB table into a self-managing data store that automatically handles cleanup operations. The TTL feature operates as a background process that continuously scans for expired items and removes them without impacting your application's read or write performance. This serverless approach to data lifecycle management eliminates the need for manual cleanup scripts or scheduled batch jobs.

<img width="406" height="107" alt="image-4" src="https://github.com/user-attachments/assets/e49bf87e-1f8b-4365-998b-9bd4cb7eafba" />


### **2. Configure CloudWatch Monitoring for TTL Activity:**

CloudWatch provides comprehensive monitoring capabilities for TTL operations, enabling you to track deletion patterns and verify the effectiveness of your data lifecycle policies. The `TimeToLiveDeletedItemCount` metric specifically tracks TTL deletions and helps optimize retention strategies to ensure TTL configurations align with business requirements for data management and cost control.

<img width="651" height="659" alt="image-5" src="https://github.com/user-attachments/assets/6c1d648a-4d55-4b99-9f44-b32faa2b5706" />


### **3. Seed Sample Session Data:**

Creating items with appropriate TTL timestamps demonstrates how applications can implement automatic data expiration. The Unix epoch time format provides precise control over when items should expire, allowing for flexible retention policies based on business requirements. Each item can have its own expiration time, enabling fine-grained data lifecycle management.

<img width="1180" height="573" alt="image-6" src="https://github.com/user-attachments/assets/2de9177a-d2a6-47fb-a9b9-b3807afe7f8a" />


## Validation & Testing

#### **1. Verify TTL Configuration:**

```
aws dynamodb describe-time-to-live --table-name $(terraform output -raw dynamodb_table_name) --region us-east-1
```

Expected output: `TimeToLiveStatus: ENABLED` with `AttributeName: expires_at`.

<img width="614" height="130" alt="image-7" src="https://github.com/user-attachments/assets/819f7c6f-588e-4f99-8744-a3b7bd817587" />


#### **2. Confirm Seeded Sample Data:**

```
aws dynamodb scan --table-name $(terraform output -raw dynamodb_table_name) --region us-east-1 --output table
```

<img width="498" height="568" alt="image-8" src="https://github.com/user-attachments/assets/1865bde6-ff52-4b96-ba18-08dda08d7304" />


#### **3. Test Real-Time Expiration:**

```
TEST_TTL=$(($(date +%s) + 60))
aws dynamodb put-item --table-name $(terraform output -raw dynamodb_table_name) --region us-east-1 --item {"user_id":{"S":"test_user"},"session_id":{"S":"test_session"},"expires_at":{"N":"'$TEST_TTL'"}}
```

Expected output: the item is retrievable immediately via `get-item`, then disappears on its own within minutes to a few hours as DynamoDB's background TTL sweeper processes the deletion.

<img width="579" height="388" alt="image-9" src="https://github.com/user-attachments/assets/83154e3e-d956-4e22-bc02-346279214991" />

