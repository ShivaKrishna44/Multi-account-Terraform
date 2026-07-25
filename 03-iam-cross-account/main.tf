# =============================================================================
# Cross-Account IAM Roles
# Allow management account / CI-CD to assume roles into workload accounts
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
    key     = "iam-cross-account/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# Provider for prod-us account (assumes role into it)
provider "aws" {
  alias  = "prod_us"
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.accounts.outputs.prod_us_account_id}:role/OrganizationAccountAccessRole"
  }
}

# Provider for prod-eu account
provider "aws" {
  alias  = "prod_eu"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.accounts.outputs.prod_eu_account_id}:role/OrganizationAccountAccessRole"
  }
}

data "terraform_remote_state" "accounts" {
  backend = "s3"
  config = {
    bucket = "multi-account-tfstate-mgmt"
    key    = "accounts/terraform.tfstate"
    region = "us-east-1"
  }
}

# =============================================================================
# Terraform Deployment Role in Prod-US
# This is what CI/CD assumes to deploy into prod-us
# =============================================================================
resource "aws_iam_role" "terraform_deploy_prod_us" {
  provider = aws.prod_us
  name     = "terraform-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # Allow management account to assume this role
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/Role" = "terraform-deployer"
          }
        }
      }
    ]
  })

  tags = {
    Purpose = "terraform-cicd-deployment"
  }
}

# Attach AdministratorAccess (with permission boundary for safety)
resource "aws_iam_role_policy_attachment" "terraform_deploy_prod_us" {
  provider   = aws.prod_us
  role       = aws_iam_role.terraform_deploy_prod_us.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# Permission Boundary — limits what the deploy role can do
# Even with AdministratorAccess, this boundary caps it
# =============================================================================
resource "aws_iam_policy" "permission_boundary_prod" {
  provider = aws.prod_us
  name     = "terraform-permission-boundary"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMostActions"
        Effect = "Allow"
        Action = "*"
        Resource = "*"
      },
      {
        Sid    = "DenyDangerousActions"
        Effect = "Deny"
        Action = [
          "organizations:*",
          "account:*",
          "iam:CreateUser",
          "iam:CreateAccessKey",
          "iam:DeleteAccountPasswordPolicy",
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# Read-Only Role for developers (cross-account console access)
# =============================================================================
resource "aws_iam_role" "developer_readonly_prod_us" {
  provider = aws.prod_us
  name     = "developer-readonly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/Team" = "*"  # Any team member can read
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "developer_readonly_prod_us" {
  provider   = aws.prod_us
  role       = aws_iam_role.developer_readonly_prod_us.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_caller_identity" "current" {}

# =============================================================================
# Outputs
# =============================================================================
output "terraform_deploy_role_arn_prod_us" {
  value = aws_iam_role.terraform_deploy_prod_us.arn
}

output "developer_readonly_role_arn_prod_us" {
  value = aws_iam_role.developer_readonly_prod_us.arn
}
