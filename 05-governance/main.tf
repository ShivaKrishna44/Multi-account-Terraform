# =============================================================================
# Governance — AWS Config Rules + GuardDuty (Organization-wide)
# Automatically detects compliance violations across all accounts
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
    key     = "governance/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# =============================================================================
# AWS Config — Compliance Rules
# Detects: unencrypted resources, public access, missing tags
# =============================================================================

resource "aws_config_configuration_recorder" "main" {
  name     = "org-config-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
}

# IAM role for Config
resource "aws_iam_role" "config_role" {
  name = "aws-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# =============================================================================
# Config Rules — What We Monitor
# =============================================================================

# Rule 1: S3 buckets must be encrypted
resource "aws_config_config_rule" "s3_encryption" {
  name = "s3-bucket-server-side-encryption-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 2: S3 buckets must NOT be public
resource "aws_config_config_rule" "s3_public_read" {
  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 3: EBS volumes must be encrypted
resource "aws_config_config_rule" "ebs_encryption" {
  name = "encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 4: RDS instances must be encrypted
resource "aws_config_config_rule" "rds_encryption" {
  name = "rds-storage-encrypted"

  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 5: Required tags on all resources
resource "aws_config_config_rule" "required_tags" {
  name = "required-tags"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key   = "Environment"
    tag2Key   = "Team"
    tag3Key   = "CostCenter"
  })

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 6: IAM root user should not have access keys
resource "aws_config_config_rule" "root_no_access_keys" {
  name = "iam-root-access-key-check"

  source {
    owner             = "AWS"
    source_identifier = "IAM_ROOT_ACCESS_KEY_CHECK"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# =============================================================================
# GuardDuty — Threat Detection (Organization-wide)
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

# Enable GuardDuty for all org accounts (delegated admin)
resource "aws_guardduty_organization_configuration" "main" {
  detector_id                      = aws_guardduty_detector.main.id
  auto_enable_organization_members = "ALL"

  datasources {
    s3_logs {
      auto_enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
  }
}

# =============================================================================
# Outputs
# =============================================================================
output "config_rules" {
  value = [
    aws_config_config_rule.s3_encryption.name,
    aws_config_config_rule.s3_public_read.name,
    aws_config_config_rule.ebs_encryption.name,
    aws_config_config_rule.rds_encryption.name,
    aws_config_config_rule.required_tags.name,
    aws_config_config_rule.root_no_access_keys.name,
  ]
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}
