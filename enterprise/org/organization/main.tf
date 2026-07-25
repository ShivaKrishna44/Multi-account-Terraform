# =============================================================================
# Organization + OUs + SCPs (same as 01-organization but pipeline-ready)
# =============================================================================

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-tfstate-mgmt"
    key            = "org/organization/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" { region = "us-east-1" }

# Organization
resource "aws_organizations_organization" "org" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "sso.amazonaws.com",
  ]
  feature_set          = "ALL"
  enabled_policy_types = ["SERVICE_CONTROL_POLICY", "TAG_POLICY"]
}

# OUs
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads_us" {
  name      = "Workloads-US"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads_eu" {
  name      = "Workloads-EU"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.org.roots[0].id
}

# SCP: Restrict US accounts to US regions only
resource "aws_organizations_policy" "restrict_us" {
  name = "restrict-to-us-regions"
  type = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Action    = "*"
      Resource  = "*"
      Condition = { StringNotEquals = { "aws:RequestedRegion" = ["us-east-1", "us-west-2"] } }
    }]
  })
}

resource "aws_organizations_policy_attachment" "us_scp" {
  policy_id = aws_organizations_policy.restrict_us.id
  target_id = aws_organizations_organizational_unit.workloads_us.id
}

# SCP: Restrict EU accounts to EU regions only
resource "aws_organizations_policy" "restrict_eu" {
  name = "restrict-to-eu-regions"
  type = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Action    = "*"
      Resource  = "*"
      Condition = { StringNotEquals = { "aws:RequestedRegion" = ["eu-west-1", "eu-central-1"] } }
    }]
  })
}

resource "aws_organizations_policy_attachment" "eu_scp" {
  policy_id = aws_organizations_policy.restrict_eu.id
  target_id = aws_organizations_organizational_unit.workloads_eu.id
}

# SCP: Protect security services (org-wide)
resource "aws_organizations_policy" "protect_security" {
  name = "protect-security-services"
  type = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "guardduty:DeleteDetector", "config:StopConfigurationRecorder"]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "protect_root" {
  policy_id = aws_organizations_policy.protect_security.id
  target_id = aws_organizations_organization.org.roots[0].id
}

# Outputs (used by other steps)
output "org_id" { value = aws_organizations_organization.org.id }
output "root_id" { value = aws_organizations_organization.org.roots[0].id }
output "ou_security_id" { value = aws_organizations_organizational_unit.security.id }
output "ou_workloads_us_id" { value = aws_organizations_organizational_unit.workloads_us.id }
output "ou_workloads_eu_id" { value = aws_organizations_organizational_unit.workloads_eu.id }
output "ou_sandbox_id" { value = aws_organizations_organizational_unit.sandbox.id }
