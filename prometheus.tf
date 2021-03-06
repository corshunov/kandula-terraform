# Key pair.
resource "tls_private_key" "prometheus" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "prometheus_private_key" {
  content = tls_private_key.prometheus.private_key_pem
  filename          = "${local.keys_path}/prometheus.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "prometheus" {
  key_name   = "prometheus"
  public_key = tls_private_key.prometheus.public_key_openssh
}


# User data.
data "template_file" "consul_prometheus" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
    consul_version = var.consul_version
    consul_encrypt_key = var.consul_encrypt_key
    node_exporter_version = var.node_exporter_version
    prometheus_dir = var.prometheus_dir
    config = <<EOF
"node_name": "prometheus",
"enable_script_checks": true,
"server": false
    EOF
  }
}

data "template_file" "prometheus" {
  template = file("${local.templates_path}/prometheus.sh.tpl")

  vars = {
      prometheus_version = var.prometheus_version
      prometheus_dir = var.prometheus_dir
  }
}

data "template_file" "filebeat_prometheus" {
  template = file("${local.templates_path}/filebeat.sh.tpl")

  vars = {
      servname = "prometheus"
  }
}

data "template_cloudinit_config" "prometheus" {
  part {
    content = data.template_file.consul_prometheus.rendered
  }

  part {
    content = data.template_file.prometheus.rendered
  }

  part {
    content = data.template_file.filebeat_prometheus.rendered
  }
}


# Instance.
resource "aws_instance" "prometheus" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.prometheus_instance_type
  key_name                    = aws_key_pair.prometheus.key_name
  subnet_id                   = aws_subnet.private.*.id[1]
  vpc_security_group_ids      = [aws_security_group.consul.id]
  user_data                   = data.template_cloudinit_config.prometheus.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "Prometheus"
  }

  depends_on = [
    aws_route.public, aws_route.private
  ]
}


# Load balancer.
resource "aws_lb" "prometheus" {
  name                        = "prometheus"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul.id]
}

resource "aws_lb_listener" "prometheus_https" {
  load_balancer_arn = aws_lb.prometheus.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_iam_server_certificate.kandula_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }
}

resource "aws_alb_listener" "prometheus_http" {
  load_balancer_arn = aws_lb.prometheus.arn
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

resource "aws_lb_target_group" "prometheus" {
  name = "prometheus"
  port = 9090
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "prometheus" {
  target_group_arn = aws_lb_target_group.prometheus.id
  target_id        = aws_instance.prometheus.id
  port             = 9090
}
