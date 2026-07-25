# Enterprise Multi-Account AWS — Full Implementation

Everything in one repo. All applied via CI/CD pipeline. No manual terraform apply.

## Structure

```
enterprise/
├── .github/workflows/
│   ├── org-management.yml        ← Pipeline for org/account/SCP changes
│   ├── infra-prod-us.yml         ← Pipeline for prod-us infrastructure
│   ├── infra-dev-us.yml          ← Pipeline for dev-us infrastructure
│   └── infra-prod-eu.yml         ← Pipeline for prod-eu infrastructure
│
├── org/                           ← Level 1: Organization governance
│   ├── organization/              ← Org + OUs + SCPs
│   ├── accounts/                  ← Account creation
│   ├── iam/                       ← Cross-account roles
│   └── security/                  ← CloudTrail + GuardDuty + Config
│
├── infra/                         ← Level 2: Infrastructure per account
│   ├── prod-us/                   ← VPC + EKS + RDS in us-east-1
│   ├── dev-us/                    ← VPC + EKS (smaller) in us-east-1
│   └── prod-eu/                   ← VPC + EKS in eu-west-1
│
├── modules/                       ← Shared reusable modules
│   ├── vpc/                       ← VPC module (used by all infra)
│   ├── eks/                       ← EKS module (used by all infra)
│   └── rds/                       ← RDS module
│
└── environments/                  ← Per-environment variable files
    ├── prod-us.tfvars
    ├── dev-us.tfvars
    └── prod-eu.tfvars
```

## Flow

```
Developer pushes to branch
    ↓
Creates PR
    ↓
Pipeline detects WHICH folder changed:
    ├── org/* changed     → runs org-management pipeline (plan only on PR)
    ├── infra/prod-us/*   → runs infra-prod-us pipeline (plan only on PR)
    └── infra/dev-us/*    → runs infra-dev-us pipeline (plan only on PR)
    ↓
Team reviews plan in PR comment
    ↓
PR merged to main
    ↓
Pipeline runs terraform apply automatically
```

## Deploy Order (First Time)

```
1. org/organization   → Creates Organization + OUs + SCPs
2. org/accounts       → Creates AWS accounts in OUs
3. org/iam            → Creates cross-account deploy roles
4. org/security       → Enables CloudTrail + GuardDuty
5. infra/prod-us      → Deploys VPC + EKS in prod-us account
6. infra/dev-us       → Deploys VPC + EKS in dev-us account
7. infra/prod-eu      → Deploys VPC + EKS in prod-eu account
```


---

## How the Pipeline Works (Interview Explanation)

```
Developer pushes .tf change to feature branch
    ↓
Creates Pull Request
    ↓
GitHub Actions detects WHICH folder changed:
    ├── org/* changed        → org-management pipeline triggers
    ├── infra/prod-us/*      → infra-prod-us pipeline triggers
    └── modules/* changed    → ALL infra pipelines trigger (shared code)
    ↓
Pipeline runs terraform plan
    ↓
Plan output posted as PR comment (team reviews what will change)
    ↓
Team approves PR → merges to main
    ↓
Pipeline runs terraform apply automatically (no human types 'apply')
    ↓
Infrastructure created/updated in the correct AWS account
```

---

## What Each Pipeline Does

| Pipeline | Runs When | AWS Account | What It Deploys |
|----------|-----------|-------------|-----------------|
| `org-management.yml` | `org/**` changes | Management account | Organization, OUs, SCPs, CloudTrail, GuardDuty |
| `infra-prod-us.yml` | `infra/prod-us/**` changes | Prod-US account (via assume role) | VPC, EKS, RDS in us-east-1 |
| `infra-dev-us.yml` | `infra/dev-us/**` changes | Dev-US account (via assume role) | VPC, EKS (smaller) in us-east-1 |
| `infra-prod-eu.yml` | `infra/prod-eu/**` changes | Prod-EU account (via assume role) | VPC, EKS in eu-west-1 |

---

## How Cross-Account Deploy Works

```
GitHub Actions (OIDC — no stored credentials)
    ↓
AssumeRoleWithWebIdentity
    ↓
Gets 15-min temporary credentials for SPECIFIC account
    ↓
terraform apply runs inside THAT account only
```

Each account has a `terraform-deploy-role` that trusts the GitHub OIDC provider.
The pipeline can ONLY access the account its role allows — no lateral movement.

---

## Key Design Decisions (What to Say in Interviews)

| Decision | Why |
|----------|-----|
| Separate state per environment | One bad apply can't corrupt another env's state |
| Modules for VPC/EKS | DRY — one change updates all envs. Consistent infrastructure. |
| .tfvars per environment | Same code, different config. Prod gets t3.large, dev gets t3.medium |
| DynamoDB lock on state | Prevents two people applying simultaneously |
| OIDC (no stored keys) | Zero-trust. No AWS credentials in GitHub secrets. |
| Plan on PR, apply on merge | Peer review before any change hits production |
| Separate pipeline per account | Blast radius — prod-us failure doesn't affect prod-eu |

---

## Hands-On Steps (Tomorrow)

### Prerequisites
1. S3 buckets for state (one per account):
```bash
aws s3 mb s3://enterprise-tfstate-mgmt --region us-east-1
aws s3 mb s3://enterprise-tfstate-prod-us --region us-east-1
aws s3 mb s3://enterprise-tfstate-dev-us --region us-east-1
```

2. DynamoDB table for locking:
```bash
aws dynamodb create-table --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

3. GitHub OIDC provider in AWS (for pipeline auth):
```bash
# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Deploy Order
```bash
# From laptop (first time) or via pipeline after setup:

# 1. Org governance
cd enterprise/org/organization
terraform init && terraform apply

# 2. Security (CloudTrail + GuardDuty)
cd ../security
terraform init && terraform apply

# 3. Infrastructure (prod-us)
cd ../../infra/prod-us
terraform init && terraform apply -var-file=../../environments/prod-us.tfvars

# 4. Infrastructure (dev-us)
cd ../dev-us
terraform init && terraform apply -var-file=../../environments/dev-us.tfvars
```

After first deploy, all subsequent changes go through PR → pipeline → auto-apply.

---

## Interview Answer (The Full Picture)

> "We have a single Terraform repo with two layers. Layer 1 is organization governance — OUs, SCPs, cross-account roles, CloudTrail — managed by the platform team, applied via a dedicated pipeline to the management account. Layer 2 is infrastructure per account — VPC, EKS, databases — using shared modules with per-environment tfvars. Each environment has its own pipeline that assumes a role into its specific account via OIDC. Nobody runs apply manually. PR creates a plan, team reviews, merge triggers apply. State is in S3 with DynamoDB locking. This gives us audit trail, peer review, blast radius isolation, and zero standing credentials."
