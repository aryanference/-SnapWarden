# SnapWarden

**Automated Multi-Region EBS Snapshot Lifecycle Management on AWS**

*Formerly ebs-guardian*

---

## Overview

ebs-guardian is a production-grade, serverless backup automation system for Amazon EBS volumes. It combines AWS Lambda, EventBridge, SNS, and Terraform to deliver a fully hands-off snapshot lifecycle — from creation through retention enforcement and automated cleanup — across every active region in your AWS account.

Designed as a Site Reliability Engineering portfolio project, it demonstrates the operational disciplines of infrastructure automation, least-privilege security, observability, and day-2 lifecycle management at scale.

---

## What It Does

On every scheduled run, ebs-guardian performs two coordinated operations:

**1. Multi-Region Snapshot Creation**

The Lambda function queries every opted-in AWS region for EC2 volumes tagged with the configured backup tag (`Snapshot=true` by default). For each qualifying volume it creates a point-in-time EBS snapshot, tagging every snapshot with metadata for traceability: source region, volume ID, creation date, and the `ManagedBy: ebs-guardian` marker used by retention enforcement.

**2. Retention-Based Snapshot Purge**

After creating new snapshots, ebs-guardian scans all regions for snapshots it manages and deletes those older than the configured retention window (default: 7 days). This closes the lifecycle loop and prevents unbounded storage cost accumulation.

**3. Structured Execution Report**

A structured report summarising snapshots created, snapshots purged, and any per-region errors is published to an SNS topic and delivered to the configured email address after every run.

---

## Architecture

```
                    EventBridge Rule
                    (cron schedule)
                          |
                          v
                   AWS Lambda (Python 3.12)
                   [SnapWarden]
                          |
            +-------------+-------------+
            |                           |
            v                           v
   All Active AWS Regions        Amazon SNS Topic
   - Describe Volumes            - Execution report
   - Create Snapshots            - Email notification
   - Purge Expired Snapshots
```

**Infrastructure components managed by Terraform:**

| Component | Purpose |
|---|---|
| `aws_lambda_function` | Core snapshot and retention logic |
| `aws_iam_role` + inline policy | Least-privilege execution identity |
| `aws_cloudwatch_event_rule` | EventBridge schedule trigger |
| `aws_sns_topic` + subscription | Operator notification channel |
| `aws_cloudwatch_log_group` | Centralised log retention (30 days) |

---

## Project Structure

```
ebs-guardian/
├── lambda_function.py          # Multi-region snapshot creation + retention enforcement
└── terraform/
    ├── main.tf                 # All AWS resource definitions
    ├── variables.tf            # Parameterised configuration
    ├── outputs.tf              # Resource ARNs and identifiers
    └── lambda_function.zip     # Packaged Lambda deployment artifact
```

---

## Key Features

- **True multi-region coverage** — dynamically discovers all opted-in regions; no hardcoded list
- **Automated retention enforcement** — purges snapshots beyond the configured age window
- **Configurable via Terraform variables** — schedule, retention period, backup tag, email, region
- **Least-privilege IAM** — scoped inline policy; no use of `AdministratorAccess` or broad managed policies
- **Structured execution reports** — per-region breakdown of create/purge counts and errors via SNS
- **CloudWatch Logs integration** — structured log output with explicit retention policy
- **Fully serverless** — zero idle compute cost; Lambda executes only on schedule
- **Tagged resource management** — every managed snapshot is tagged with `ManagedBy: ebs-guardian` for deterministic lifecycle tracking

---

## Technologies

| Technology | Role |
|---|---|
| AWS Lambda (Python 3.12) | Snapshot and lifecycle orchestration logic |
| Amazon EventBridge | Cron-based scheduling |
| Amazon SNS | Operator alerting and execution reports |
| Amazon EBS | Storage volumes under management |
| AWS IAM | Execution identity with least-privilege policy |
| Amazon CloudWatch Logs | Execution observability |
| Terraform (>= 1.3) | Infrastructure as Code provisioning |

---

## Prerequisites

- Terraform >= 1.3
- AWS CLI configured with credentials that have sufficient IAM privileges to create the resources defined in `main.tf`
- Python 3.x (local, for packaging the Lambda)
- An active email address for SNS subscription confirmation

---

## Deployment

### 1. Package the Lambda function

From the repository root:

```bash
zip terraform/lambda_function.zip lambda_function.py
```

### 2. Configure variables

Edit `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
aws_region          = "us-east-1"
notification_email  = "ops@yourcompany.com"
retention_days      = 7
schedule_expression = "cron(0 2 * * ? *)"   # 02:00 UTC daily
snapshot_tag_key    = "Snapshot"
snapshot_tag_value  = "true"
```

### 3. Provision infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Confirm with `yes` when prompted.

### 4. Confirm SNS subscription

AWS will send a confirmation email to the address specified in `notification_email`. Click the confirmation link before the first scheduled run.

### 5. Tag your EBS volumes

Any EBS volume you want backed up must carry the backup tag:

```
Key:   Snapshot
Value: true
```

---

## Configuration Reference

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region for the provider and supporting resources |
| `lambda_function_name` | `ebs-guardian` | Name of the Lambda function |
| `notification_email` | — | Email address for execution reports |
| `schedule_expression` | `cron(0 2 * * ? *)` | EventBridge schedule (rate or cron syntax) |
| `retention_days` | `7` | Age threshold in days; older managed snapshots are deleted |
| `snapshot_tag_key` | `Snapshot` | EBS volume tag key identifying volumes for backup |
| `snapshot_tag_value` | `true` | EBS volume tag value identifying volumes for backup |

---

## Validation

After deployment, verify the following:

| Check | Where |
|---|---|
| Lambda execution | AWS Console > Lambda > Monitor > CloudWatch Logs |
| Snapshot creation | AWS Console > EC2 > Snapshots (filter by `ManagedBy: ebs-guardian`) |
| Retention purge | Lambda logs — look for `Purged expired snapshot` entries |
| Execution report | Inbox for `notification_email` |
| EventBridge rule | AWS Console > EventBridge > Rules — confirm rule is `Enabled` |

---

## Outputs

After `terraform apply`, the following values are exported:

| Output | Description |
|---|---|
| `lambda_function_name` | Deployed function name |
| `lambda_function_arn` | Function ARN |
| `sns_topic_arn` | SNS topic ARN for alerts |
| `eventbridge_rule_arn` | Scheduling rule ARN |
| `iam_role_arn` | Lambda execution role ARN |
| `log_group_name` | CloudWatch Log Group name |

---

## SRE Relevance

This project reflects several core Site Reliability Engineering disciplines:

- **Toil elimination** — replaces manual snapshot creation and deletion with fully automated lifecycle management
- **Operational observability** — structured CloudWatch logs and SNS reports give operators clear signal on system health
- **Security posture** — IAM policy scoped to the exact actions required; no wildcard service-level permissions
- **Cost governance** — retention enforcement prevents snapshot sprawl and unbounded EBS storage costs
- **Resilience through redundancy** — multi-region coverage ensures backups exist even if a single region is impaired
- **Infrastructure as Code** — all resources are reproducible, version-controlled, and auditable through Terraform

---

## License

MIT License © 2026 SnapWarden

---

*SnapWarden — Site Reliability Engineering Portfolio — Infrastructure Automation*
