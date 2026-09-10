terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Optionally set profile, access_key, secret_key via env vars or
  # shared credentials file (~/.aws/credentials). No hardcoded creds here.
}
