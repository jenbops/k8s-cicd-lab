# versions.tf
#
# WHAT THIS FILE DOES:
# Pins the Terraform/OpenTofu version and the AWS provider version.
# This is the file OpenTofu reads first — before it knows anything about
# EC2 instances, it needs to know which "plugin" (provider) to load to
# talk to AWS's API, and which version of that plugin to trust.
#
# WHY THIS MATTERS FOR LEARNING:
# Infrastructure-as-Code tools work by translating your declarative config
# (.tf files describing "what should exist") into API calls against a
# real cloud provider. The `provider` block below is what makes AWS calls
# possible at all — without it, `aws_instance` in main.tf would be a
# meaningless resource type with no implementation behind it.
#
# We use OpenTofu here instead of HashiCorp's Terraform CLI because
# Terraform switched to the Business Source License (BSL) in 2023, which
# is not OSI-approved open source. OpenTofu is the community-maintained,
# MPL-2.0-licensed fork (now a CNCF project) — same HCL syntax, same
# state file format, same provider ecosystem. Everything in this project
# runs identically whether you install `tofu` or `terraform` as the
# binary; we just default to `tofu` in the commands throughout this repo.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
