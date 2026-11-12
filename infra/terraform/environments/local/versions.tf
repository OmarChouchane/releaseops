terraform {
  required_version = ">= 1.14.0"

  required_providers {
    # Exact minor pins; the committed lock file pins patch and hashes
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Partial config: run.sh passes -backend-config; state lives in gitignored .releaseops/ (secret)
  backend "local" {}
}
