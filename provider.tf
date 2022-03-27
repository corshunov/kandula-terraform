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

    tls = {
      source  = "hashicorp/tls"
      version = "3.1.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.1.2"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.9.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
  }

  backend "s3" {
    bucket  = "kandula-project"
    key     = "terraform-state"
    region  = "us-east-1"
    acl     = "private"
    encrypt = true
  }
}

provider "aws" {
  region  = var.aws_region

#  default_tags {
#    tags = {
#      Project = "kandula"
#    }
#  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

provider "kubectl" {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
    load_config_file       = false
}
