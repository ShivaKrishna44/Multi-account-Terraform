# =============================================================================
# Service Control Policies (SCPs)
# These are HARD LIMITS — even account admins cannot bypass them
# =============================================================================

# -----------------------------------------------------------------------------
# SCP: Restrict US workloads to US regions ONLY
# Attached to: OU Workloads-US
# Effect: Nobody in US accounts can create resources in EU/Asia regions
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "restrict_to_us_regions" {
  name        = "restrict-to-us-regions"
  description = "Deny all actions outside US regions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonUSRegions"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = ["us-east-1", "us-west-2"]
          }
          # Allow global services (IAM, Organizations, etc.)
          ArnNotLike = {
            "aws:PrincipalARN" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "us_region_scp" {
  policy_id = aws_organizations_policy.restrict_to_us_regions.id
  target_id = aws_organizations_organizational_unit.workloads_us.id
}

# -----------------------------------------------------------------------------
# SCP: Restrict EU workloads to EU regions ONLY
# Attached to: OU Workloads-EU
# Effect: Nobody in EU accounts can create resources in US/Asia regions
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "restrict_to_eu_regions" {
  name        = "restrict-to-eu-regions"
  description = "Deny all actions outside EU regions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonEURegions"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = ["eu-west-1", "eu-central-1"]
          }
          ArnNotLike = {
            "aws:PrincipalARN" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "eu_region_scp" {
  policy_id = aws_organizations_policy.restrict_to_eu_regions.id
  target_id = aws_organizations_organizational_unit.workloads_eu.id
}

# -----------------------------------------------------------------------------
# SCP: Prevent disabling security services (ALL accounts)
# Attached to: Root (applies to entire org)
# Effect: Nobody can turn off CloudTrail, GuardDuty, Config
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "protect_security_services" {
  name        = "protect-security-services"
  description = "Prevent disabling CloudTrail, GuardDuty, Config"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDisablingSecurity"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "config:StopConfigurationRecorder",
          "config:DeleteConfigurationRecorder",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "protect_security_root" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = aws_organizations_organization.org.roots[0].id
}

# -----------------------------------------------------------------------------
# SCP: Deny expensive services in Sandbox
# Attached to: OU Sandbox
# Effect: Developers can't launch expensive resources in sandbox
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "sandbox_restrictions" {
  name        = "sandbox-restrictions"
  description = "Restrict expensive services in sandbox accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyExpensiveServices"
        Effect = "Deny"
        Action = [
          "redshift:*",
          "emr:*",
          "sagemaker:CreateNotebookInstance",
          "ec2:RunInstances"
        ]
        Resource = "*"
        Condition = {
          # Only deny large instance types
          StringLike = {
            "ec2:InstanceType" = ["*.xlarge", "*.2xlarge", "*.4xlarge", "*.8xlarge", "*.metal"]
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "sandbox_scp" {
  policy_id = aws_organizations_policy.sandbox_restrictions.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}
