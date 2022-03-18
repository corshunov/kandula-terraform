terraform {
  required_version = ">= 0.12"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = ">=2.7.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.68.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2.0"
    }
  }

  backend "s3" {
    bucket  = "aleks-terraform"
    key     = "Kandula_State_Development"
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