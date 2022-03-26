resource "random_string" "eks_cluster_name_suffix" {
  length  = 8
  special = false
}

resource "aws_security_group" "eks_worker" {
  name_prefix = "eks_worker"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "17.24.0"
  cluster_name    = local.eks_cluster_name
  cluster_version = var.k8s_version
  subnets         = aws_subnet.private.*.id
  enable_irsa     = true
  vpc_id          = aws_vpc.vpc.id
  manage_aws_auth = true

  worker_groups   = [
    {
      name                          = "kandula"
      instance_type                 = var.k8s_instance_type
      asg_desired_capacity          = var.k8s_count
      additional_security_group_ids = [aws_security_group.eks_worker.id, aws_security_group.consul.id]
    }
  ]

  map_roles       = [
    {
      rolearn  = aws_iam_role.jenkins_agent.arn
      username = "jenkins-agent"
      groups   = ["system:masters"]
    }
  ]
 
  map_users       = [
    {
      userarn  = data.aws_caller_identity.current.arn
      username = "caller"
      groups   = ["system:masters"]
    }
  ]
}

resource "kubernetes_service_account" "kandula" {
  metadata {
    name      = var.k8s_service_account_name
    namespace = var.k8s_service_account_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = module.iam_assumable_role_admin.iam_role_arn
    }
  }

  depends_on = [
    module.eks
  ]
}

module "iam_assumable_role_admin" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "~> 4.7.0"
  create_role                   = true
  role_name                     = "kandula"
  provider_url                  = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  role_policy_arns              = ["arn:aws:iam::aws:policy/AmazonEC2FullAccess"]
  oidc_fully_qualified_subjects = ["system:serviceaccount:${var.k8s_service_account_namespace}:${var.k8s_service_account_name}"]
}

resource "kubernetes_namespace" "consul" {
  metadata {
    annotations = {
      name = "consul"
    }
    labels = {
      mylabel = "consul"
    }
    name = "consul"
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    annotations = {
      name = "monitoring"
    }
    labels = {
      mylabel = "monitoring"
    }
    name = "monitoring"
  }
}

resource "kubernetes_namespace" "logging" {
  metadata {
    annotations = {
      name = "logging"
    }
    labels = {
      mylabel = "logging"
    }
    name = "logging"
  }
}

resource "kubernetes_secret" "aws_creds" {
  metadata {
    name = "kandula-secrets"
  }

  data = {
    aws_region            = var.aws_region
    aws_secret_access_key = var.kandula_aws_secret_access_key
    aws_access_key_id     = var.kandula_aws_access_key_id
    flask_secret_key      = var.flask_secret_key
    postgres_pasword      = var.postgres_kandula_password
  }

  type = "Opaque"
}

resource "kubernetes_secret" "consul" {
  metadata {
    name      = "kandula-secrets"
    namespace = "consul"
  }

  data = {
    consul_encrypt_key = var.consul_encrypt_key
  }

  type = "Opaque"
}




