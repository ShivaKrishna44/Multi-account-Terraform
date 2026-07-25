terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Store state in S3 (management account)
  backend "s3" {
    bucket  = "multi-account-tfstate-mgmt"
    key     = "organization/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# This runs in the MANAGEMENT account
provider "aws" {
  region = "us-east-1"
}
