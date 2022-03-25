output "consul_dns" {
  value = aws_lb.consul.dns_name
}

output "prometheus_dns" {
  value = aws_lb.prometheus.dns_name
}

output "grafana_dns" {
  value = aws_lb.grafana.dns_name
}

output "jenkins_main_dns" {
  value = aws_lb.jenkins_main.dns_name
}

output "kibana_dns" {
  value = aws_lb.kibana.dns_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  value = local.eks_cluster_name
}

output "bastion_ip" {
  value = aws_instance.bastion.public_ip
}
