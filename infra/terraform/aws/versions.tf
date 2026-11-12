terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # For shared use enable remote state (versioned, encrypted, locked bucket):
  # backend "s3" {
  #   bucket       = "<your-tfstate-bucket>"
  #   key          = "releaseops/eks/terraform.tfstate"
  #   region       = "eu-central-1"
  #   encrypt      = true
  #   use_lockfile = true   # S3-native locking, no DynamoDB table needed
  # }
}
