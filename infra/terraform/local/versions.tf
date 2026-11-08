terraform {
  required_version = ">= 1.14.0"

  required_providers {
    # Exact minor pins; .terraform.lock.hcl (committed) pins the exact patch + hashes.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5.0"
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

  # Partial configuration: run.sh passes `-backend-config=path=<state file>` so the state lives in
  # the gitignored .releaseops/ directory with 0600 permissions. The state contains generated
  # credentials (DB and Grafana passwords) - treat it as a secret. See docs/adr/0004-terraform-boundaries.md.
  backend "local" {}
}
