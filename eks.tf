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
  source                 = "terraform-aws-modules/eks/aws"
  version                = "17.24.0"
  cluster_name           = local.eks_cluster_name
  cluster_version        = var.k8s_version
  subnets                = aws_subnet.private.*.id
  enable_irsa            = true
  vpc_id                 = aws_vpc.vpc.id
  manage_aws_auth        = true
  write_kubeconfig       = true
  kubeconfig_output_path = pathexpand("~/.kube/config")

  worker_groups          = [
    {
      name                          = "kandula"
      instance_type                 = var.k8s_instance_type
      asg_desired_capacity          = var.k8s_count
      additional_security_group_ids = [aws_security_group.eks_worker.id, aws_security_group.consul.id]
    }
  ]

  map_roles              = [
    {
      rolearn  = aws_iam_role.jenkins_agent.arn
      username = "jenkins-agent"
      groups   = ["system:masters"]
    }
  ]
 
  map_users              = [
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

resource "kubernetes_secret" "default" {
  metadata {
    name      = "kandula-secrets"
    namespace = "default"
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

resource "kubernetes_namespace" "consul" {
  metadata {
    annotations = {
      name = "consul"
    }
    name = "consul"
  }
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

  depends_on = [
    kubernetes_namespace.consul
  ]
}

resource "helm_release" "consul" {
  repository = "https://helm.releases.hashicorp.com"
  name       = "consul"
  chart      = "consul"
  namespace  = "consul"

  values = [
    "${file("${local.k8s_path}/consul_values.yaml")}"
  ]

  set {
    name  = "global.name"
    value = "consul"
  }

  depends_on = [
    kubernetes_namespace.consul
  ]
}

resource "kubectl_manifest" "coredns" {
  yaml_body = file("${local.k8s_path}/coredns_cm.yaml")
  force_new = true

  depends_on = [
    helm_release.consul
  ]
}

resource "kubernetes_namespace" "filebeat" {
  metadata {
    annotations = {
      name = "filebeat"
    }
    name = "filebeat"
  }
}

resource "kubernetes_service_account" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = "filebeat"
    labels    = {
      k8s-app = "filebeat"
    }
  }

  depends_on = [
    kubernetes_namespace.filebeat
  ]
}

resource "kubernetes_cluster_role" "filebeat" {
  metadata {
    name   = "filebeat"
    labels = {
      k8s-app = "filebeat"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [
    kubernetes_service_account.filebeat
  ]
}

resource "kubernetes_cluster_role_binding" "filebeat" {
  metadata {
    name = "filebeat"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "filebeat"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "filebeat"
    namespace = "filebeat"
  }

  depends_on = [
    kubernetes_cluster_role.filebeat
  ]
}

resource "kubernetes_config_map" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = "filebeat"
    labels    = {
      k8s-app = "filebeat"
    }
  }

  data = {
    "filebeat.yml" = <<EOF
    filebeat.inputs:
    - type: container
      paths:
        - /var/log/containers/*.log
      processors:
        - add_kubernetes_metadata:
            host: $${NODE_NAME}
            matchers:
            - logs_path:
                logs_path: "/var/log/containers/"
        - drop_event:
            when:
              not:
                has_fields: ['kubernetes.container.name']
        - drop_event:
            when:
              equals:
                kubernetes.container.name: "filebeat"
        - decode_json_fields:
            fields: ["message"]
            max_depth: 1
            target: ""
            overwrite_keys: true
            when:
              regexp:
                message: '^{'
    processors:
      - add_cloud_metadata:
      - add_host_metadata:
    setup.template.name: "filebeat-kandula"
    setup.template.pattern: "filebeat-kandula"
    setup.template.settings:
      index.number_of_shards: 1

    setup.ilm.enabled: false

    setup.dashboards.enabled: true
    setup.kibana.host: "kibana.service.consul:5601"

    output.elasticsearch:
      hosts: ['elasticsearch.service.consul:9200']
      index: "filebeat-kandula-%%{[agent.version]}-%%{+yyyy.MM.dd}"
    EOF
  }

  depends_on = [
    kubernetes_namespace.filebeat
  ]
}

resource "kubernetes_daemonset" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = "filebeat"
    labels    = {
      k8s-app = "filebeat"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "filebeat"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app = "filebeat"
        }
      }

      spec {
        service_account_name = "filebeat"
        termination_grace_period_seconds = 30
        host_network = true
        dns_policy = "ClusterFirstWithHostNet"

        container {
          name  = "filebeat"
          image = "docker.elastic.co/beats/filebeat-oss:7.17.1"

          args  = [
            "-c", "/etc/filebeat.yml",
            "-e",
          ]

          env {
            name = "NODE_NAME"

            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          security_context {
            run_as_user = 0
          }

          resources {
            limits = {
              memory = "200Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "100Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/filebeat.yml"
            read_only  = true
            sub_path   = "filebeat.yml"
          }

          volume_mount {
            name       = "data"
            mount_path = "/usr/share/filebeat/data"
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }
        }

        volume {
          name = "config"

          config_map {
            default_mode = "0640"
            name         = "filebeat"
          }
        }

        volume {
          name = "varlibdockercontainers"
            
          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        volume {
          name = "varlog"
            
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "data"
          
          host_path {
            path = "/var/lib/filebeat-data"
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.filebeat,
    kubernetes_cluster_role_binding.filebeat
  ]
}

resource "kubernetes_namespace" "prometheus" {
  metadata {
    annotations = {
      name = "prometheus"
    }
    name = "prometheus"
  }
}

resource "helm_release" "prometheus" {
  repository = "https://prometheus-community.github.io/helm-charts"
  name       = "prometheus-node-exporter"
  chart      = "prometheus-node-exporter"
  namespace  = "prometheus"

  depends_on = [
    kubernetes_namespace.prometheus
  ]
}
