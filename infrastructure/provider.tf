terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.47.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "4.3.0"
    }
  }

  backend "s3" {
    bucket  = "3-tier-project-statefile"
    key     = "vpc/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}


provider "aws" {
  # Configuration options
  region = var.aws_region
}