variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "bastion_instance_type" {
  type    = string
  #default = "t2.micro"
  default = "t3.medium"
}

variable "consul_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "elasticsearch_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "kibana_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "jenkins_main_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "jenkins_agent_instance_type" {
  type    = string
  #default = "t2.micro"
  default = "t3.medium"
}

variable "grafana_instance_type" {
  type    = string
  #default = "t2.micro"
  default = "t3.medium"
}

variable "postgres_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "prometheus_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "k8s_instance_type" {
  type    = string
  default = "t3.large"
}

variable "k8s_count" {
  type    = number
  default = 2
}

variable "consul_count" {
  type    = number
  default = 3
}

variable "jenkins_agent_count" {
  type    = number
  default = 2
}

variable "k8s_version" {
  type    = string
  default = "1.18"
}

variable "consul_version" {
  type    = string
  #default = "1.4.0"
  default = "1.11.4"
}

variable "node_exporter_version" {
  type    = string
  #default = "0.18.1"
  default = "1.3.1"
}

variable "prometheus_version" {
  type    = string
  #default = "2.16.0"
  default = "2.34.0"
}

variable "prometheus_dir" {
  type    = string
  default = "/opt/prometheus"
}

variable "jenkins_main_ami_account" {
  type    = string
  default = "self"
}

variable "jenkins_main_ami_name" {
  type    = string
  default = "jenkins-main"
}

variable "consul_encrypt_key" {
  type      = string
  sensitive = true
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}

variable "postgres_kandula_password" {
  type    = string
  sensitive = true
}
