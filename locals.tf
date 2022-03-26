locals {
  policies_path                 = "${path.module}/policies"
  scripts_path                  = "${path.module}/scripts"
  templates_path                = "${path.module}/templates"
  keys_path                     = "${path.module}/keys"

  eks_cluster_name              = "kandula-${random_string.eks_cluster_name_suffix.result}"
}
