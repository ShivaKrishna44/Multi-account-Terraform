# =============================================================================
# Centralized Logging — Organization CloudTrail + S3 in Security Account
# One trail covers ALL accounts in the organization
# =============================================================================

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket  = "multi-account-tfstate-mgmt"
    key     = "logging/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_organizations_organization" "current" {}

# =============================================================================
# S3 Bucket for CloudTrail logs (in management account)
# =============================================================================
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "org-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Purpose = "organization-cloudtrail"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy — allow CloudTrail from all org accounts to write
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.current.account_id}:trail/organization-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_organizations_organization.current.id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.current.account_id}:trail/organization-trail"
          }
        }
      }
    ]
  })
}

# =============================================================================
# Organization CloudTrail — covers ALL accounts automatically
# =============================================================================
resource "aws_cloudtrail" "organization" {
  name                          = "organization-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  is_organization_trail         = true  # THIS is the key — covers all accounts
  is_multi_region_trail         = true  # Logs from ALL regions
  enable_log_file_validation    = true  # Tamper detection
  include_global_service_events = true  # IAM, STS, etc.

  tags = {
    Purpose = "organization-audit-trail"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# =============================================================================
# Outputs
# =============================================================================
output "cloudtrail_name" {
  value = aws_cloudtrail.organization.name
}

output "cloudtrail_s3_bucket" {
  value = aws_s3_bucket.cloudtrail_logs.id
}
