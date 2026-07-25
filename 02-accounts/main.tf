# =============================================================================
# Create AWS Accounts and place them in correct OUs
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
    key     = "accounts/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# Get OU IDs from organization state
data "terraform_remote_state" "org" {
  backend = "s3"
  config = {
    bucket = "multi-account-tfstate-mgmt"
    key    = "organization/terraform.tfstate"
    region = "us-east-1"
  }
}

# =============================================================================
# Security Account
# =============================================================================
resource "aws_organizations_account" "security" {
  name      = "security"
  email     = "aws-security@yourcompany.com"
  parent_id = data.terraform_remote_state.org.outputs.ou_security_id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    Environment = "security"
    Purpose     = "centralized-security"
  }

  lifecycle {
    ignore_changes = [role_name]  # Can't change after creation
  }
}

# =============================================================================
# Production US Account
# =============================================================================
resource "aws_organizations_account" "prod_us" {
  name      = "prod-us"
  email     = "aws-prod-us@yourcompany.com"
  parent_id = data.terraform_remote_state.org.outputs.ou_workloads_us_id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    Environment   = "production"
    Region        = "us"
    DataResidency = "US"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

# =============================================================================
# Dev US Account
# =============================================================================
resource "aws_organizations_account" "dev_us" {
  name      = "dev-us"
  email     = "aws-dev-us@yourcompany.com"
  parent_id = data.terraform_remote_state.org.outputs.ou_workloads_us_id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    Environment   = "development"
    Region        = "us"
    DataResidency = "US"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

# =============================================================================
# Production EU Account
# =============================================================================
resource "aws_organizations_account" "prod_eu" {
  name      = "prod-eu"
  email     = "aws-prod-eu@yourcompany.com"
  parent_id = data.terraform_remote_state.org.outputs.ou_workloads_eu_id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    Environment   = "production"
    Region        = "eu"
    DataResidency = "EU"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

# =============================================================================
# Dev EU Account
# =============================================================================
resource "aws_organizations_account" "dev_eu" {
  name      = "dev-eu"
  email     = "aws-dev-eu@yourcompany.com"
  parent_id = data.terraform_remote_state.org.outputs.ou_workloads_eu_id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    Environment   = "development"
    Region        = "eu"
    DataResidency = "EU"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

# =============================================================================
# Outputs
# =============================================================================
output "security_account_id" {
  value = aws_organizations_account.security.id
}

output "prod_us_account_id" {
  value = aws_organizations_account.prod_us.id
}

output "dev_us_account_id" {
  value = aws_organizations_account.dev_us.id
}

output "prod_eu_account_id" {
  value = aws_organizations_account.prod_eu.id
}

output "dev_eu_account_id" {
  value = aws_organizations_account.dev_eu.id
}
