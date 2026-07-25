# AWS Multi-Account Terraform — Hands-On Lab

## What This Covers (Interview Topics)

1. AWS Organizations + OUs
2. Service Control Policies (SCPs) — region restriction, service restriction
3. Cross-account IAM roles (assume role from management account)
4. Account vending (automated new account creation)
5. Centralized logging (CloudTrail → S3 in log account)
6. Data residency enforcement (US vs EU)

## Architecture

```
Management Account (this is where Terraform runs)
│
├── OU: Security
│   └── security-account (CloudTrail, GuardDuty, Config)
│
├── OU: Workloads-US (SCP: only us-east-1, us-west-2)
│   ├── prod-us
│   └── dev-us
│
├── OU: Workloads-EU (SCP: only eu-west-1, eu-central-1)
│   ├── prod-eu
│   └── dev-eu
│
└── OU: Sandbox (SCP: budget limit, no prod services)
    └── developer-sandbox
```

## Deploy Order

```bash
# Step 1: Organization + OUs + SCPs
cd 01-organization
terraform init && terraform apply

# Step 2: Accounts (creates actual AWS accounts)
cd ../02-accounts
terraform init && terraform apply

# Step 3: Cross-account roles
cd ../03-iam-cross-account
terraform init && terraform apply

# Step 4: Centralized logging
cd ../04-logging
terraform init && terraform apply

# Step 5: Governance (Config rules, GuardDuty)
cd ../05-governance
terraform init && terraform apply
```

## Key Concepts for Interview

- **SCP** = hard limit, even admin can't bypass
- **Permission Boundary** = ceiling on IAM roles within an account
- **Cross-account role** = assume role into another account (no credentials stored)
- **Organization Trail** = one CloudTrail covers ALL accounts
- **Delegated Administrator** = security account manages GuardDuty/Config without being management account
