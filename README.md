# AWS Multi-Account Terraform — Hands-On Lab

## What This Does

Sets up a production-grade AWS multi-account environment with governance, security, and compliance — the way enterprises do it.

---

## Architecture

```
┌──────────────────────────────────────────────────────── ──┐
│              AWS Organizations (Management Account)       │
│                                                           │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                    Root (r-vhrn)                     │ │
│  │       SCP: protect-security-services (attached here) │ │
│  │                                                      │ │
│  │  ┌───────────┐  ┌──────────────┐  ┌──────────────┐   │ │
│  │  │ OU:       │  │ OU:          │  │ OU:          │   │ │
│  │  │ Security  │  │ Workloads-US │  │ Workloads-EU │   │ │
│  │  │           │  │              │  │              │   │ │
│  │  │ security  │  │ SCP: deny    │  │ SCP: deny    │   │ │
│  │  │ account   │  │ non-US       │  │ non-EU       │   │ │
│  │  │           │  │ regions      │  │ regions      │   │ │
│  │  │           │  │              │  │              │   │ │
│  │  │           │  │ ├─ prod-us   │  │ ├─ prod-eu   │   │ │
│  │  │           │  │ └─ dev-us    │  │ └─ dev-eu    │   │ │
│  │  └───────────┘  └──────────────┘  └──────────────┘   │ │
│  │                                                      │ │
│  │  ┌───────────┐                                       │ │
│  │  │ OU:       │                                       │ │
│  │  │ Sandbox   │                                       │ │
│  │  │           │                                       │ │
│  │  │ SCP: deny │                                       │ │
│  │  │ expensive │                                       │ │
│  │  │ services  │                                       │ │
│  │  └───────────┘                                       │ │
│  └──────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────── ─┘
```

---

## Deployment Flow (Step by Step)

### Step 1: `01-organization/` — Create Org + OUs + SCPs

```bash
cd 01-organization
terraform init    # Downloads AWS provider, sets up S3 backend
terraform apply   # Creates the following:
```

**What gets created:**

| Resource | Purpose |
|----------|---------|
| `aws_organizations_organization` | Creates the AWS Organization (enables all features + policy types) |
| `aws_organizations_organizational_unit.security` | OU for security/audit account |
| `aws_organizations_organizational_unit.workloads_us` | OU for US workloads (region-locked) |
| `aws_organizations_organizational_unit.workloads_eu` | OU for EU workloads (region-locked) |
| `aws_organizations_organizational_unit.sandbox` | OU for developer sandboxes |
| `aws_organizations_policy.restrict_to_us_regions` | SCP: DENY all non-US regions |
| `aws_organizations_policy.restrict_to_eu_regions` | SCP: DENY all non-EU regions |
| `aws_organizations_policy.protect_security_services` | SCP: Nobody can disable CloudTrail/GuardDuty |
| `aws_organizations_policy.sandbox_restrictions` | SCP: No expensive instances in sandbox |
| Policy attachments (4x) | Connects SCPs to their respective OUs |

**Outputs:**
```
org_id             = "o-fn19xdg4lz"
root_id            = "r-vhrn"
ou_security_id     = "ou-vhrn-675wu4da"
ou_workloads_us_id = "ou-vhrn-ghx1lnec"
ou_workloads_eu_id = "ou-vhrn-ixjeml2e"
ou_sandbox_id      = "ou-vhrn-q87ivi50"
```

---

### Step 2: `02-accounts/` — Create AWS Accounts in Each OU

```bash
cd ../02-accounts
terraform init    # Downloads provider, reads remote state from step 1
terraform apply   # Creates accounts and places them in correct OUs
```

**What gets created:**

| Resource | OU Placement | Effect |
|----------|-------------|--------|
| `aws_organizations_account.security` | OU: Security | Centralized audit account |
| `aws_organizations_account.prod_us` | OU: Workloads-US | Can only use us-east-1, us-west-2 |
| `aws_organizations_account.dev_us` | OU: Workloads-US | Same region restriction |
| `aws_organizations_account.prod_eu` | OU: Workloads-EU | Can only use eu-west-1, eu-central-1 |
| `aws_organizations_account.dev_eu` | OU: Workloads-EU | Same region restriction |

**Key behavior:** Each account inherits its OU's SCP automatically. The moment `prod-eu` is created in the EU OU, it CANNOT create resources in US regions — enforced by SCP, no IAM can override.

**Note:** Requires unique email per account (Gmail `+` aliases work: `you+aws-prod-us@gmail.com`)

---

### Step 3: `03-iam-cross-account/` — Create Roles for CI/CD Access

```bash
cd ../03-iam-cross-account
terraform init    # Downloads provider, reads account IDs from step 2
terraform apply   # Creates IAM roles INSIDE the workload accounts
```

**What gets created (in each workload account):**

| Resource | Purpose |
|----------|---------|
| `aws_iam_role.terraform_deploy_prod_us` | Role that CI/CD assumes to deploy into prod-us |
| `aws_iam_role.developer_readonly_prod_us` | Role that developers assume for read-only console access |
| `aws_iam_policy.permission_boundary_prod` | Hard ceiling — even with AdministratorAccess, can't touch Organizations/create IAM users |

**How cross-account works:**
```
CI/CD Pipeline (management account)
    ↓
sts:AssumeRole → arn:aws:iam::<prod-us-account>:role/terraform-deploy-role
    ↓
Gets temporary credentials (15 min) scoped to prod-us only
    ↓
Runs terraform apply inside prod-us
```

---

### Step 4: `04-logging/` — Centralized CloudTrail (All Accounts)

```bash
cd ../04-logging
terraform init
terraform apply   # Creates org-wide audit trail
```

**What gets created:**

| Resource | Purpose |
|----------|---------|
| `aws_s3_bucket.cloudtrail_logs` | Centralized S3 bucket for ALL account logs |
| `aws_s3_bucket_public_access_block` | Blocks public access (security) |
| `aws_s3_bucket_policy` | Allows CloudTrail from all org accounts to write |
| `aws_cloudtrail.organization` | Organization Trail — covers ALL accounts, ALL regions |

**Key behavior:** One trail automatically logs every API call from every account in the org. Nobody can disable it (protected by SCP from step 1). Logs are immutable in S3.

---

### Step 5: `05-governance/` — Compliance Rules + Threat Detection

```bash
cd ../05-governance
terraform init
terraform apply   # Creates Config rules + GuardDuty
```

**What gets created:**

| Resource | What It Detects |
|----------|----------------|
| Config Rule: `s3-bucket-server-side-encryption-enabled` | Unencrypted S3 buckets |
| Config Rule: `s3-bucket-public-read-prohibited` | Public S3 buckets |
| Config Rule: `encrypted-volumes` | Unencrypted EBS volumes |
| Config Rule: `rds-storage-encrypted` | Unencrypted RDS databases |
| Config Rule: `required-tags` | Resources missing Environment/Team/CostCenter tags |
| Config Rule: `iam-root-access-key-check` | Root user has access keys (bad practice) |
| `aws_guardduty_detector` | Threat detection (unusual API calls, crypto mining, etc.) |
| `aws_guardduty_organization_configuration` | Auto-enables GuardDuty for all accounts |

---

## How It All Connects

```
Step 1 creates:     Organization + OUs + SCPs (structure + hard guardrails)
     ↓ outputs OU IDs
Step 2 creates:     Accounts placed in OUs (inherit SCPs automatically)
     ↓ outputs account IDs
Step 3 creates:     IAM roles inside accounts (for CI/CD cross-account access)
     ↓
Step 4 creates:     CloudTrail covering all accounts (audit trail)
     ↓
Step 5 creates:     Config rules + GuardDuty (compliance + threat detection)
```

Each step reads outputs from the previous step via `terraform_remote_state`:
```hcl
data "terraform_remote_state" "org" {
  backend = "s3"
  config = {
    bucket = "multi-account-tfstate-mgmt"
    key    = "organization/terraform.tfstate"
    region = "us-east-1"
  }
}
# Now I can use: data.terraform_remote_state.org.outputs.ou_workloads_us_id
```

---

## Interview Topics This Covers

| Question | Answer From |
|----------|-------------|
| "How do you structure multi-account AWS?" | Step 1 (OUs) |
| "How do you enforce data residency?" | Step 1 (SCPs on US/EU OUs) |
| "Can an admin bypass the restriction?" | No — SCPs override IAM |
| "How does CI/CD deploy to multiple accounts?" | Step 3 (AssumeRole, no stored keys) |
| "How do you audit all accounts?" | Step 4 (Organization CloudTrail) |
| "How do you ensure compliance?" | Step 5 (Config rules auto-detect violations) |
| "How do you detect threats?" | Step 5 (GuardDuty org-wide) |

---

## What I Deployed (Lab Results)

```
$ terraform apply (01-organization)
✅ Organization created: o-fn19xdg4lz
✅ 4 OUs created: Security, Workloads-US, Workloads-EU, Sandbox
✅ 4 SCPs created and attached:
   - restrict-to-us-regions → Workloads-US OU
   - restrict-to-eu-regions → Workloads-EU OU
   - protect-security-services → Root (all accounts)
   - sandbox-restrictions → Sandbox OU
```

---

## Cleanup

```bash
# Destroy in reverse order
cd 05-governance && terraform destroy
cd ../04-logging && terraform destroy
cd ../03-iam-cross-account && terraform destroy
cd ../02-accounts && terraform destroy  # Note: can't delete accounts easily
cd ../01-organization && terraform destroy
```

**Warning:** Deleting AWS accounts is not instant — they go into a 90-day suspension period. The Organization itself can only be deleted when all member accounts are removed.
