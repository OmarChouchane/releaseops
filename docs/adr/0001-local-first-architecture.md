# ADR-0001: Local-first on kind; AWS as an optional, unprovisioned path

**Status:** accepted

## Context
The challenge asks for Dockerfile + Helm + Terraform-on-Kubernetes, "designed to operate seamlessly on local
machines", with free tooling. There is no cloud budget, and a reviewer must be able to reproduce the result.

## Decision
* The **source of truth is a local kind cluster** (one node, Kubernetes 1.36) on Docker, driven by one command.
* kind rather than minikube/k3d: it is what Kubernetes' own CI uses, node images are digest-pinned, and
  port mappings give stable `localhost` URLs without tunnels.
* An **optional EKS configuration** (`infra/terraform/aws`) shows how the same chart moves to a managed cluster. It
  is validated offline (`terraform validate`, `fmt`) and **never applied**; every document that mentions it says so.
* Nothing in the local path needs AWS credentials, a paid service or a public IP.

## Consequences
+ Anyone with Docker can run it; the demo is real (real Argo CD, real rollouts, real failure), not simulated.
+ Costs nothing.
− A one-node cluster cannot demonstrate node failure, multi-AZ scheduling or real load balancers.
− The AWS code can be wrong in ways `validate` cannot detect (IAM, quotas, add-on behaviour). It is labelled
  accordingly.

## Not claimed
This is not Crewmeister's infrastructure (which the author understands to be ECS-based). It is an independent
implementation of the Kubernetes variant of the challenge.
