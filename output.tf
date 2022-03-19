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
  value = aws_lb.elastic.dns_name
}

output "bastion_ip" {
  value = aws_instance.bastion.public_ip
}
