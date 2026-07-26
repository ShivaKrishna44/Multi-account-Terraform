# AWS Multi-Account Terraform — Enterprise Setup

Single repo. Two layers. All applied via CI/CD pipeline. No manual terraform apply.

---

## Architecture

```
┌────────────────────────────────────────────────────────  ──┐
│              AWS Organizations (Management Account)        │
│                                                            │
│  Root (SCP: protect CloudTrail/GuardDuty — nobody can disable)
│  │                                                         │
│  ├── OU: Security        → security account (audit/logs)   │
│  ├── OU: Workloads-US    → SCP: only us-east-1, us-west-2  │
│  │   ├── prod-us         → VPC + EKS (t3.large, 3 nodes)   │
│  │   └── dev-us          → VPC + EKS (t3.medium, 2 nodes)  │ 
│  ├── OU: Workloads-EU    → SCP: only eu-west-1, eu-central-1
│  │   └── prod-eu         → VPC + EKS (t3.large, 3 nodes)   │
│  └── OU: Sandbox         → SCP: no expensive services      │
└──────────────────────────────────────────────────────────  ┘
```

---

## Repo Structure

```
Multi-account-Terraform/
│
├── 01-organization/               ← Basic setup (lab — already deployed)
├── 02-accounts/                   ← Account creation (lab)
├── 03-iam-cross-account/          ← Cross-account roles (lab)
├── 04-logging/                    ← CloudTrail (lab)
├── 05-governance/                 ← Config rules + GuardDuty (lab)
│
└── enterprise/                    ← FULL enterprise setup (pipeline-driven)
    ├── .github/workflows/
    │   ├── org-management.yml     ← Pipeline: org/accounts/SCPs
    │   └── infra-prod-us.yml     ← Pipeline: VPC+EKS in prod-us
    │
    ├── org/                       ← Layer 1: Governance (management account)
    │   ├── organization/          ← Org + OUs + SCPs
    │   └── security/              ← CloudTrail + GuardDuty
    │
    ├── infra/                     ← Layer 2: Infrastructure (per account)
    │   ├── prod-us/               ← VPC + EKS in prod-us account
    │   └── dev-us/                ← VPC + EKS (smaller) in dev-us account
    │
    ├── modules/                   ← Shared reusable Terraform modules
    │   ├── vpc/                   ← VPC module (all envs use this)
    │   └── eks/                   ← EKS module (all envs use this)
    │
    └── environments/              ← Per-environment config
        ├── prod-us.tfvars         ← t3.large, 3 nodes, 10 max
        ├── dev-us.tfvars          ← t3.medium, 2 nodes, 4 max
        └── prod-eu.tfvars         ← Same as prod-us but eu-west-1
```

---

## Pipeline Flow (How Changes Get Applied)

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

| Pipeline | Triggers On | AWS Account | Deploys |
|----------|------------|-------------|---------|
| `org-management.yml` | `org/**` changes | Management account | Organization, OUs, SCPs, CloudTrail, GuardDuty |
| `infra-prod-us.yml` | `infra/prod-us/**` changes | Prod-US (via assume role) | VPC, EKS in us-east-1 |
| `infra-dev-us.yml` | `infra/dev-us/**` changes | Dev-US (via assume role) | VPC, EKS (smaller) in us-east-1 |
| `infra-prod-eu.yml` | `infra/prod-eu/**` changes | Prod-EU (via assume role) | VPC, EKS in eu-west-1 |

---

## How Cross-Account Deploy Works (Zero-Trust)

```
GitHub Actions (OIDC — no stored AWS credentials)
    ↓
AssumeRoleWithWebIdentity → 15-min temporary credentials
    ↓
Scoped to ONE specific account only
    ↓
terraform apply runs inside THAT account
```

No long-lived keys. No shared credentials. Each account has its own role.

---

## Key Design Decisions

| Decision | Why |
|----------|-----|
| Separate state per environment | One bad apply can't corrupt another env |
| Shared modules (vpc/, eks/) | DRY — same code, different config per env |
| .tfvars per environment | Prod = large, Dev = small. Same templates. |
| DynamoDB state locking | Prevents two people applying simultaneously |
| OIDC (no stored keys) | Zero-trust. Short-lived tokens only. |
| Plan on PR, apply on merge | Peer review before any prod change |
| Separate pipeline per account | Blast radius isolation |

---

## Lab Results (What I've Deployed)

```
✅ Organization created: o-fn19xdg4lz
✅ 4 OUs created: Security, Workloads-US, Workloads-EU, Sandbox
✅ 4 SCPs created and attached:
   - restrict-to-us-regions → Workloads-US OU
   - restrict-to-eu-regions → Workloads-EU OU
   - protect-security-services → Root (all accounts)
   - sandbox-restrictions → Sandbox OU
✅ S3 backend configured for state management
```

---

## Hands-On Steps

### Prerequisites
```bash
# S3 buckets for state
aws s3 mb s3://enterprise-tfstate-mgmt --region us-east-1
aws s3 mb s3://enterprise-tfstate-prod-us --region us-east-1
aws s3 mb s3://enterprise-tfstate-dev-us --region us-east-1

# DynamoDB for state locking
aws dynamodb create-table --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1

# GitHub OIDC provider (for pipeline auth)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Deploy Order
```bash
# 1. Org governance
cd enterprise/org/organization
terraform init && terraform apply

# 2. Security
cd ../security
terraform init && terraform apply

# 3. Prod-US infrastructure
cd ../../infra/prod-us
terraform init && terraform apply -var-file=../../environments/prod-us.tfvars

# 4. Dev-US infrastructure
cd ../dev-us
terraform init && terraform apply -var-file=../../environments/dev-us.tfvars
```

After first deploy, all changes go through PR → pipeline → auto-apply.

---

## Summary

> "We have a single Terraform repo with two layers. Layer 1 is organization governance — OUs, SCPs, cross-account roles, CloudTrail — applied via a pipeline to the management account. Layer 2 is infrastructure per account — VPC, EKS, databases — using shared modules with per-environment tfvars. Each environment has its own pipeline that assumes a role into that specific account via OIDC. Nobody runs apply manually. PR creates a plan, team reviews, merge triggers apply. State is in S3 with DynamoDB locking."
