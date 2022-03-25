resource "random_string" "eks_cluster_name_suffix" {
  length  = 8
  special = false
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
      additional_security_group_ids = [aws_security_group.consul.id]
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
    name      = local.k8s_service_account_name
    namespace = local.k8s_service_account_namespace
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
  oidc_fully_qualified_subjects = ["system:serviceaccount:${local.k8s_service_account_namespace}:${local.k8s_service_account_name}"]
}
