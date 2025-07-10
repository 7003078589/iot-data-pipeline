# terraform/versions.tf

# Specifies the required Terraform version and AWS provider version.
# This ensures consistency across different environments and prevents unexpected behavior
# due to version mismatches.
terraform {
  required_version = ">= 1.0.0" # Specify a minimum required Terraform version

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a compatible version of the AWS provider
    }
  }
}