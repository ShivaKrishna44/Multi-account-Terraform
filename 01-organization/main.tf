# =============================================================================
# AWS Organizations — Create the org structure
# =============================================================================

resource "aws_organizations_organization" "org" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "sso.amazonaws.com",
  ]

  feature_set = "ALL"

  # Enable all policy types
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]
}

# =============================================================================
# Organizational Units (OUs)
# =============================================================================

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

# =============================================================================
# Outputs
# =============================================================================

output "org_id" {
  value = aws_organizations_organization.org.id
}

output "root_id" {
  value = aws_organizations_organization.org.roots[0].id
}

output "ou_security_id" {
  value = aws_organizations_organizational_unit.security.id
}

output "ou_workloads_us_id" {
  value = aws_organizations_organizational_unit.workloads_us.id
}

output "ou_workloads_eu_id" {
  value = aws_organizations_organizational_unit.workloads_eu.id
}

output "ou_sandbox_id" {
  value = aws_organizations_organizational_unit.sandbox.id
}
