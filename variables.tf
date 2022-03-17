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

variable "consul_server_count" {
  type    = number
  default = 3
}

variable "consul_version" {
  type    = string
  default = "1.4.0"
}

variable "prometheus_version" {
  type    = string
  default = "2.16.0"
}

variable "prometheus_dir" {
  type    = string
  default = "/opt/prometheus"
}

variable "prometheus_conf_dir" {
  type    = string
  default = "/etc/prometheus"
}

variable "node_exporter_version" {
  type    = string
  default = "0.18.1"
}
