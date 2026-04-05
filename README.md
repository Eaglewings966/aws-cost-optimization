<div align="center">

# AWS Cloud Cost Optimization Engine

[![Terraform](https://img.shields.io/badge/Terraform-1.5+-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-FF9900?style=for-the-badge&logo=awslambda&logoColor=white)](https://aws.amazon.com/lambda/)
[![AWS Budgets](https://img.shields.io/badge/AWS-Budgets-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/aws-cost-management/aws-budgets/)
[![CloudWatch](https://img.shields.io/badge/AWS-CloudWatch-FF4F8B?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/cloudwatch/)
[![Cost Explorer](https://img.shields.io/badge/AWS-Cost_Explorer-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![SNS](https://img.shields.io/badge/AWS-SNS-FF4F8B?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/sns/)
[![S3](https://img.shields.io/badge/AWS-S3-569A31?style=for-the-badge&logo=amazons3&logoColor=white)](https://aws.amazon.com/s3/)
[![License](https://img.shields.io/badge/License-MIT-22c55e?style=for-the-badge)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/Eaglewings966/aws-cost-optimization?style=for-the-badge&color=3b82f6)](https://github.com/Eaglewings966/aws-cost-optimization)

**A fully automated AWS cost optimization engine that detects idle
infrastructure, enforces resource tagging, optimizes storage costs,
and alerts engineering teams before cloud spend becomes a crisis.**

[📖 Full Technical Article](https://emmanuelubani.hashnode.dev) •
[💼 LinkedIn](https://linkedin.com/in/ubaniemmanuel) •
[🐙 GitHub](https://github.com/Eaglewings966) •
[🌐 Portfolio](https://ops-run.lovable.app)

</div>

---

## Table of Contents

- [Problem Statement](#problem-statement)
- [Business Impact](#business-impact)
- [Architecture Overview](#architecture-overview)
- [Architecture Decisions](#architecture-decisions)
- [DevOps Toolchain](#devops-toolchain)
- [Project Structure](#project-structure)
- [Security Implementation](#security-implementation)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [How the Lambda Works](#how-the-lambda-works)
- [Production Considerations](#production-considerations)
- [Key Lessons Learned](#key-lessons-learned)
- [Destroy Everything](#destroy-everything)
- [Author](#author)

---

## Problem Statement

Uncontrolled cloud spend is one of the most common operational
failures in engineering organisations that move fast. It does not
happen because engineers are careless. It happens because AWS
makes it easy to provision resources and hard to track what is
running, who owns it, and whether it is still needed.

The pattern is always the same. A developer spins up an EC2
instance for a load test and forgets to stop it. An S3 bucket
fills with old build artifacts that nobody queries. Resources
get created without tags, making cost attribution impossible.
The monthly bill arrives and nobody can explain what caused
the spike.

This platform addresses that pattern with five automated controls.
A Lambda function identifies and stops EC2 instances that have
been idle for 24 hours. AWS Budgets sends alerts at 50%, 80%,
and 100% of a $20 monthly threshold before spend becomes
uncontrollable. S3 lifecycle policies automatically transition
objects to cheaper storage tiers and expire old versions.
An IAM tagging policy blocks resource creation without the
four required tags. And a CloudWatch dashboard gives the
engineering team unified visibility into all cost signals
in one place.

---

## Business Impact

| Metric | Without Optimization | With This Platform |
|--------|---------------------|-------------------|
| Idle EC2 detection | Manual monthly review | Automated every 24 hours |
| Forgotten instance cost | Accumulates silently | Stopped automatically |
| Budget breach awareness | Discovered on monthly bill | Alert at 50%, 80%, 100% |
| S3 storage cost | All objects in Standard tier | Auto-tiered to IA and Glacier |
| Resource tagging compliance | Optional and inconsistent | Enforced at creation via IAM |
| Cost visibility | Multiple disconnected consoles | Single CloudWatch dashboard |
| Alert response time | Days after breach | Real-time via SNS and email |
| Untagged resource attribution | Impossible | Blocked before creation |

---

## Architecture Overview
┌──────────────────────────────────────────────────────────────┐
│                    COST OPTIMIZATION FLOW                    │
│                                                              │
│  EventBridge — runs every 24 hours                          │
│          │                                                   │
│          ▼                                                   │
│  Lambda — stop_idle_instances                               │
│          │                                                   │
│          ├── Queries CloudWatch for EC2 CPU metrics         │
│          ├── Identifies instances below 5% CPU for 24h      │
│          ├── Stops idle instances via EC2 API               │
│          └── Publishes detailed report to SNS               │
│                                                              │
│  AWS Budgets — monitors monthly spend                       │
│          │                                                   │
│          ├── Alert at 50% of $20 ($10 actual spend)        │
│          ├── Alert at 80% of $20 ($16 actual spend)        │
│          ├── Alert at 100% of $20 ($20 actual spend)       │
│          └── Forecasted alert at 80% threshold             │
│                                                              │
│  S3 Lifecycle — automatic storage tiering                   │
│          │                                                   │
│          ├── Standard → Standard-IA at 30 days             │
│          ├── Standard-IA → Glacier at 90 days              │
│          ├── Delete objects at 365 days                     │
│          ├── Abort incomplete multipart uploads at 7 days   │
│          └── Expire old versions at 90 days                │
│                                                              │
│  IAM Tagging Policy — blocks untagged resource creation     │
│          │                                                   │
│          └── Requires: Environment, Owner,                  │
│              Project, CostCenter on all EC2, S3, RDS        │
│                                                              │
│  CloudWatch Dashboard — unified cost visibility             │
│          │                                                   │
│          ├── EC2 CPU utilization across all instances       │
│          ├── Lambda invocation count and errors             │
│          ├── Lambda duration metrics                        │
│          └── Active cost alarms                            │
└──────────────────────────────────────────────────────────────┘

---

## Architecture Decisions

**Why Lambda over AWS Instance Scheduler**
AWS Instance Scheduler is a managed solution but requires
CloudFormation and has limited customisation. A Lambda function
gives full control over the idle detection logic, the reporting
format, and the notification content. The exemption tag pattern
allows specific instances to opt out without changing the
core automation.

**Why EventBridge over CloudWatch Events**
EventBridge is the modern replacement for CloudWatch Events
and supports more sophisticated event routing. The 24-hour
rate expression triggers the Lambda once per day, which is
the right frequency for idle instance detection without
generating excessive API calls to CloudWatch metrics.

**Why SNS over direct email from Lambda**
SNS decouples the notification delivery from the Lambda
function. Additional subscribers, such as Slack via Lambda
or PagerDuty via HTTPS endpoint, can be added to the SNS
topic without changing the Lambda code. The topic becomes
the central notification hub for all cost events.

**Why IAM Deny policy over AWS Config rules**
AWS Config rules detect non-compliant resources after they
are created. An IAM Deny policy prevents the creation entirely.
For tagging enforcement, prevention is more effective than
detection because it eliminates the remediation step.

**Why Terraform default_tags over per-resource tags**
The Terraform AWS provider supports default_tags at the
provider level. Every resource created by this configuration
automatically receives the four required tags without
repeating the tag block in every resource definition.
This eliminates the risk of a resource being deployed
without tags due to a missed tag block.

---

## DevOps Toolchain

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | 1.5+ | All infrastructure provisioning and lifecycle |
| AWS Lambda | Python 3.12 | Idle instance detection and automated stopping |
| AWS Budgets | Latest | Monthly spend threshold alerts at 50%, 80%, 100% |
| AWS SNS | Latest | Centralized notification delivery |
| AWS EventBridge | Latest | 24-hour schedule triggering Lambda |
| AWS CloudWatch | Latest | Metrics, dashboard, and alarms |
| AWS Cost Explorer | Latest | Cost and usage data via IAM permissions |
| AWS S3 | Latest | Storage with automated lifecycle tiering |
| AWS IAM | Latest | Tagging enforcement and least-privilege Lambda role |

---

## Project Structure
aws-cost-optimization/
│
├── terraform/
│   ├── main.tf              # All AWS resources — SNS, Budget, Lambda,
│   │                        # EventBridge, S3, CloudWatch, IAM
│   ├── variables.tf         # All configurable input variables
│   ├── outputs.tf           # Resource ARNs, URLs, and useful commands
│   ├── versions.tf          # Provider version constraints
│   └── terraform.tfvars     # Actual variable values (gitignored)
│
├── lambda/
│   └── stop_idle_instances.py  # Lambda function — idle detection
│                                # and automated stopping logic
│
├── policies/
│   └── tagging-policy.json     # IAM deny policy for untagged resources
│                                # (reference copy — deployed via Terraform)
│
├── .gitignore               # Excludes tfstate, tfvars, .terraform/, zips
└── README.md

---

## Security Implementation

**Least privilege Lambda IAM role**
The Lambda execution role has four scoped permission sets.
EC2 read and stop permissions are restricted to DescribeInstances,
DescribeInstanceStatus, and StopInstances only. CloudWatch
permissions cover metric reads only. SNS permission is scoped
to the specific topic ARN. CloudWatch Logs permissions are
scoped to the specific log group ARN. No wildcard actions.
No wildcard resources where avoidable.

**IAM tagging enforcement**
The Deny policy blocks EC2, S3, and RDS resource creation
when any of the four required tags are absent. This prevents
the creation of untagged resources that cannot be attributed
to an owner, project, or cost center for billing analysis.

**S3 security hardening**
The cost optimizer S3 bucket has versioning enabled,
server-side encryption with AES256, and all public access
blocked at the bucket level. Objects cannot be made public
regardless of individual object ACL settings.

**No secrets in code or Git**
The Lambda function uses environment variables injected
by Terraform for all configuration values. The SNS topic
ARN, CPU threshold, and environment label are passed as
environment variables at deploy time. No credentials
or sensitive values appear in the Lambda code or in
any committed file.

**Terraform state protection**
terraform.tfvars and all .tfstate files are excluded
from Git via .gitignore. State contains resource ARNs
and account identifiers that should not be committed
to version control.

---

## Prerequisites

| Tool | Version | Verify |
|------|---------|--------|
| AWS CLI | v2.x | `aws --version` |
| Terraform | v1.5+ | `terraform --version` |
| Python | 3.12 | `python3 --version` |
| AWS Account | Any | `aws sts get-caller-identity` |

> Ensure your AWS CLI credentials have permissions to create
> Lambda, IAM roles, SNS topics, Budgets, S3, CloudWatch,
> and EventBridge resources.

---

## Deployment

### Step 1 — Deploy All Infrastructure
```bash
cd terraform
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply --auto-approve
```

### Step 2 — Confirm SNS Email Subscription

Check devopsalert3@gmail.com for a confirmation email
from AWS SNS. Click the confirmation link. Budget alerts
and Lambda reports will not arrive until confirmed.

### Step 3 — Invoke Lambda Manually to Test
```bash
aws lambda invoke \
  --function-name cost-optimizer-stop-idle-instances \
  --region us-east-1 \
  --log-type Tail \
  response.json && cat response.json
```

Expected Lambda test output in the terminal includes `instances_evaluated`, `instances_stopped`, and `instances_skipped` in the JSON response body.

### Step 4 — View CloudWatch Dashboard
```bash
terraform output cloudwatch_dashboard_url
```

Open the URL in your browser to see the unified cost dashboard.

### Step 5 — Verify S3 Lifecycle Policies
```bash
BUCKET=$(terraform output -raw s3_bucket_name)
aws s3api get-bucket-lifecycle-configuration \
  --bucket $BUCKET --region us-east-1
```

---

## How the Lambda Works
EventBridge triggers Lambda every 24 hours
│
▼
Lambda calls ec2:DescribeInstances
Filters for running instances
Excludes instances tagged CostOptimizer=exempt
│
▼
For each instance:
Lambda calls cloudwatch:GetMetricStatistics
Retrieves average CPU over past 24 hours
│
CPU < 5%?
/          
YES           NO
│             │
▼             ▼
Stop instance  Add to skipped list
Add to stopped list
│
▼
Lambda publishes detailed report to SNS
Report delivered to devops-alerts@gmail.com

---

## Production Considerations

| Gap | Current State | Production Solution |
|-----|--------------|---------------------|
| Multi-account cost visibility | Single account | AWS Organizations with Cost Explorer multi-account |
| Rightsizing recommendations | Not implemented | AWS Compute Optimizer integration |
| Reserved Instance analysis | Not implemented | Cost Explorer RI utilization reports |
| Savings Plans recommendations | Not implemented | Savings Plans API via Lambda |
| Automated tagging remediation | Deny at creation | AWS Config with auto-remediation Lambda |
| Cost anomaly detection | Budget thresholds only | AWS Cost Anomaly Detection with ML |
| Slack notifications | Email only | SNS to Lambda to Slack webhook |
| Terraform remote state | Local state | S3 backend with DynamoDB locking |

---

## Key Lessons Learned

**Lambda packaging with Terraform archive provider**
The archive_file data source automatically zips the Lambda
Python file before every terraform apply. This eliminates
the manual step of creating and uploading a ZIP file.
If the Python source changes, the source_code_hash
changes, and Terraform automatically redeploys the function.

**SNS subscription confirmation is blocking**
AWS Budgets and the Lambda SNS publish both work immediately
after terraform apply. But notifications are silently
discarded until the email subscription is confirmed.
Always confirm the subscription before testing.

**Terraform default_tags reduces tagging drift**
Setting default_tags at the provider level guarantees
every resource receives the required tags regardless
of whether the individual resource block remembers to
include them. This is more reliable than per-resource
tag blocks for large configurations.

**IAM Deny policies must use Null condition carefully**
The Null condition operator checks whether a tag key
is absent from the request. Using Null with "true"
means the key is missing. This correctly blocks
resource creation when tags are not provided. Using
StringEquals to check tag values requires the caller
to know the exact permitted values in advance.

**EventBridge rate expressions vs cron expressions**
Rate expressions like rate(24 hours) are simpler but
run relative to the function creation time. Cron
expressions like cron(0 6 * * ? *) run at a specific
UTC time daily. For cost optimization, a specific
morning run time is more useful because reports arrive
before the engineering team starts work. Use cron
in production.

---

## Destroy Everything
```bash
cd terraform
terraform destroy --auto-approve
```

Verify in AWS console that Lambda, SNS topic, Budget,
CloudWatch dashboard, S3 bucket, IAM policy, EventBridge
rule, and CloudWatch alarm are all removed.

---

## Author

<div align="center">

**Emmanuel Ubani**
Cloud and DevOps Engineer — Lagos, Nigeria

*From zoo volunteer to Cloud and DevOps Engineer.*
*Building production-grade infrastructure in public.*

[![LinkedIn](https://img.shields.io/badge/LinkedIn-ubaniemmanuel-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://linkedin.com/in/ubaniemmanuel)
[![GitHub](https://img.shields.io/badge/GitHub-Eaglewings966-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/Eaglewings966)
[![Hashnode](https://img.shields.io/badge/Hashnode-emmanuelubani-2962FF?style=for-the-badge&logo=hashnode&logoColor=white)](https://emmanuelubani.hashnode.dev)
[![Medium](https://img.shields.io/badge/Medium-emmaubani966-000000?style=for-the-badge&logo=medium&logoColor=white)](https://medium.com/@emmaubani966)
[![Docker Hub](https://img.shields.io/badge/Docker_Hub-eaglewings6-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://hub.docker.com/u/eaglewings6)
[![Portfolio](https://img.shields.io/badge/Portfolio-ops--run.lovable.app-6366f1?style=for-the-badge)](https://ops-run.lovable.app)

| # | Project | Repository |
|---|---------|------------|
| 1 | AWS IAM Multi-Account Setup | [aws-iam-multi-account-setup](https://github.com/Eaglewings966/aws-iam-multi-account-setup) |
| 2 | GitHub Actions CI/CD Pipeline | [github-actions-cicd-pipeline](https://github.com/Eaglewings966/github-actions-cicd-pipeline) |
| 3 | Kubernetes EKS Deployment | [eks-kubernetes-deployment](https://github.com/Eaglewings966/eks-kubernetes-deployment) |
| 4 | GitOps Platform with Argo CD | [argocd-gitops-platform](https://github.com/Eaglewings966/argocd-gitops-platform) |
| 5 | AWS Cost Optimization Engine | This repository |

</div>
