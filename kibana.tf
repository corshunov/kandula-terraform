# Key pair.
resource "tls_private_key" "kibana" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "kibana_private_key" {
  content = tls_private_key.kibana.private_key_pem
  filename          = "${local.keys_path}/kibana.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "kibana" {
  key_name   = "kibana"
  public_key = tls_private_key.kibana.public_key_openssh
}


# User data.
data "template_file" "consul_kibana" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
    consul_version = var.consul_version
    consul_encrypt_key = var.consul_encrypt_key
    node_exporter_version = var.node_exporter_version
    prometheus_dir = var.prometheus_dir
    config = <<EOF
"node_name": "kibana",
"enable_script_checks": true,
"server": false
    EOF
  }
}

data "local_file" "kibana" {
  filename = "${local.scripts_path}/kibana.sh"
}

data "template_file" "filebeat_kibana" {
  template = file("${local.templates_path}/filebeat.sh.tpl")

  vars = {
      servname = "kibana"
  }
}

data "template_cloudinit_config" "kibana" {
  part {
    content = data.template_file.consul_kibana.rendered
  }

  part {
    content = data.local_file.kibana.content
  }

  part {
    content = data.template_file.filebeat_kibana.rendered
  }
}


# Instance.
resource "aws_instance" "kibana" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.kibana_instance_type
  key_name                    = aws_key_pair.kibana.key_name
  subnet_id                   = aws_subnet.private.*.id[1]
  vpc_security_group_ids      = [aws_security_group.consul.id]
  user_data                   = data.template_cloudinit_config.kibana.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "Kibana"
  }

  depends_on = [
    aws_route.public, aws_route.private
  ]
}


# Load balancer.
resource "aws_lb" "kibana" {
  name                        = "kibana"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul.id]
}

resource "aws_lb_listener" "kibana" {
  load_balancer_arn = aws_lb.kibana.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kibana.arn
  }
}

resource "aws_lb_target_group" "kibana" {
  name = "kibana"
  port = 5601
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "kibana" {
  target_group_arn = aws_lb_target_group.kibana.id
  target_id        = aws_instance.kibana.id
  port             = 5601
}
