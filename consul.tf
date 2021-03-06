# Key pair.
resource "tls_private_key" "consul" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "consul_private_key" {
  content = tls_private_key.consul.private_key_pem
  filename          = "${local.keys_path}/consul.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "consul" {
  key_name   = "consul"
  public_key = tls_private_key.consul.public_key_openssh
}


# Security group.
resource "aws_security_group" "consul" {
  name   = "consul"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "consul_all_inside_ingress" {
  type        = "ingress"
  protocol    = -1
  from_port   = 0
  to_port     = 0
  self        = true
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_http_inside_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_8080_inside_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 8080
  to_port     = 8080
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_https_inside_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_all_egress" {
  type        = "egress"
  protocol    = -1
  from_port   = 0
  to_port     = 0
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}


# User data.
data "template_file" "consul" {
  count    = var.consul_count
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
    consul_version = var.consul_version
    consul_encrypt_key = var.consul_encrypt_key
    node_exporter_version = var.node_exporter_version
    prometheus_dir = var.prometheus_dir
    config = <<EOF
"node_name": "consul-${count.index+1}",
"server": true,
"bootstrap_expect": 3,
"ui": true,
"client_addr": "0.0.0.0",
"telemetry": {
   "prometheus_retention_time": "10m"
}
    EOF
  }
}

data "template_file" "filebeat_consul" {
  count    = var.consul_count
  template = file("${local.templates_path}/filebeat.sh.tpl")

  vars = {
      servname = "consul"
  }
}

data "template_cloudinit_config" "consul" {
  count    = var.consul_count
  part {
    content = data.template_file.consul.*.rendered[count.index]
  }

  part {
    content = data.template_file.filebeat_consul.*.rendered[count.index]
  }
}


# Instance.
resource "aws_instance" "consul" {
  count                  = var.consul_count
  ami                    = data.aws_ami.ubuntu_18.id
  instance_type          = var.consul_instance_type
  key_name               = aws_key_pair.consul.key_name
  subnet_id              = aws_subnet.private.*.id[count.index % var.az_count]
  vpc_security_group_ids = [aws_security_group.consul.id]
  user_data              = data.template_cloudinit_config.consul.*.rendered[count.index]
  iam_instance_profile   = aws_iam_instance_profile.consul.name

  tags = {
    Name = "Consul ${count.index+1}"
    consul_server = "true"
  }

  depends_on = [
    aws_route.public, aws_route.private
  ]
}


# Load balancer.
resource "aws_lb" "consul" {
  name                        = "consul"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul.id]
}

resource "aws_lb_listener" "consul_https" {
  load_balancer_arn = aws_lb.consul.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_iam_server_certificate.kandula_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul.arn
  }
}

resource "aws_alb_listener" "consul_http" {
  load_balancer_arn = aws_lb.consul.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_target_group" "consul" {
  name = "consul"
  port = 8500
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "consul" {
  count            = length(aws_instance.consul)
  target_group_arn = aws_lb_target_group.consul.id
  target_id        = aws_instance.consul.*.id[count.index]
  port             = 8500
}
