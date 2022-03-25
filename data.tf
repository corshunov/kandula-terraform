data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

data "http" "local_ip" {
  url = "http://ifconfig.me"
}

data "aws_ami" "ubuntu_18" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "jenkins_main" {
  most_recent = true
  owners      = [var.jenkins_main_ami_account]

  filter {
    name   = "name"
    values = [var.jenkins_main_ami_name]
  }
}

data "aws_eks_cluster" "eks" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_id
}
