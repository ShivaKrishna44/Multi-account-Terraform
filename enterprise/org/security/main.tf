# =============================================================================
# Centralized Security — CloudTrail + GuardDuty + Config Rules
# Runs from management account, covers all org accounts
# =============================================================================

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-tfstate-mgmt"
    key            = "org/security/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" { region = "us-east-1" }

data "aws_caller_identity" "current" {}
data "aws_organizations_organization" "current" {}

# =============================================================================
# Organization CloudTrail (covers ALL accounts)
# =============================================================================

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "enterprise-cloudtrail-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_organizations_organization.current.id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

resource "aws_cloudtrail" "org" {
  name                          = "enterprise-org-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_organization_trail         = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  include_global_service_events = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# =============================================================================
# GuardDuty (Org-wide threat detection)
# =============================================================================

resource "aws_guardduty_detector" "main" {
  enable = true
  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
  }
}

resource "aws_guardduty_organization_configuration" "main" {
  detector_id                      = aws_guardduty_detector.main.id
  auto_enable_organization_members = "ALL"
}

# =============================================================================
# Outputs
# =============================================================================
output "cloudtrail_bucket" { value = aws_s3_bucket.cloudtrail.id }
output "guardduty_detector_id" { value = aws_guardduty_detector.main.id }
