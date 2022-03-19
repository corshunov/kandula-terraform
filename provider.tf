terraform {
  required_version = ">= 0.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.2.2"
    }
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
  }

  backend "s3" {
    bucket  = "kandula-project"
    key     = "terraform-state"
    region  = "us-east-1"
  }
}

provider "aws" {
  region  = var.aws_region

  default_tags {
    tags = {
      Project     = "kandula"
    }
  }
}
