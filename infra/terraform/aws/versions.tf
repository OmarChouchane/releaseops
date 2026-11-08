terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # Remote state is mandatory for anything shared (state holds secrets and must be locked).
  # Create the bucket once (versioned, encrypted, private), then uncomment:
  #
  # backend "s3" {
  #   bucket       = "<your-tfstate-bucket>"
  #   key          = "releaseops/eks/terraform.tfstate"
  #   region       = "eu-central-1"
  #   encrypt      = true
  #   use_lockfile = true   # S3-native locking, no DynamoDB table needed
  # }
}
