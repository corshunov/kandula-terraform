# Key pair.
resource "tls_private_key" "grafana" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "grafana_private_key" {
  content = tls_private_key.grafana.private_key_pem
  filename          = "${local.keys_path}/grafana.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "grafana" {
  key_name   = "grafana"
  public_key = tls_private_key.grafana.public_key_openssh
}


# User data.
data "template_file" "consul_grafana" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
    consul_version = var.consul_version
    consul_encrypt_key = var.consul_encrypt_key
    node_exporter_version = var.node_exporter_version
    prometheus_dir = var.prometheus_dir
    config = <<EOF
"node_name": "grafana",
"enable_script_checks": true,
"server": false
    EOF
  }
}

data "local_file" "grafana" {
  filename = "${local.scripts_path}/grafana.sh"
}

data "template_file" "filebeat_grafana" {
  template = file("${local.templates_path}/filebeat.sh.tpl")

  vars = {
      servname = "grafana"
  }
}

data "template_cloudinit_config" "grafana" {
  part {
    content = data.template_file.consul_grafana.rendered
  }

  part {
    content = data.local_file.grafana.content
  }

  part {
    content = data.template_file.filebeat_grafana.rendered
  }
}


# Instance.
resource "aws_instance" "grafana" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.grafana_instance_type
  key_name                    = aws_key_pair.grafana.key_name
  subnet_id                   = aws_subnet.private.*.id[1]
  vpc_security_group_ids      = [aws_security_group.consul.id]
  user_data                   = data.template_cloudinit_config.grafana.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "Grafana"
  }

  depends_on = [
    aws_route.public, aws_route.private
  ]
}


# Load balancer.
resource "aws_lb" "grafana" {
  name                        = "grafana"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul.id]
}

resource "aws_lb_listener" "grafana_https" {
  load_balancer_arn = aws_lb.grafana.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_iam_server_certificate.kandula_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_alb_listener" "grafana_http" {
  load_balancer_arn = aws_lb.grafana.arn
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

resource "aws_lb_target_group" "grafana" {
  name = "grafana"
  port = 3000
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana.id
  target_id        = aws_instance.grafana.id
  port             = 3000
}
