# Key pair.
resource "tls_private_key" "elastic" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "elastic_private_key" {
  sensitive_content = tls_private_key.elastic.private_key_pem
  filename          = "${local.keys_path}/elastic.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "elastic" {
  key_name   = "elastic"
  public_key = tls_private_key.elastic.public_key_openssh
}


# User data.
data "template_file" "consul_elastic" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
      node_exporter_version = var.node_exporter_version
      prometheus_dir = var.prometheus_dir
      config = <<EOF
       "node_name": "elastic",
       "enable_script_checks": true,
       "server": false
      EOF
  }
}

data "template_file" "elastic" {
  template = file("${local.scripts_path}/elastic.sh")
}

data "template_cloudinit_config" "elastic" {
  part {
    content = data.template_file.consul_elastic.rendered
  }

  part {
    content = data.template_file.elastic.rendered
  }
}


# Instance.
resource "aws_instance" "elastic" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.elastic.key_name
  subnet_id                   = aws_subnet.private.*.id[1]
  vpc_security_group_ids      = [aws_security_group.consul.id]
  user_data                   = data.template_cloudinit_config.elastic.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "ElasticSearch"
  }
}


# Load balancer.
resource "aws_lb" "elastic" {
  name                        = "elastic"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul.id]
}

resource "aws_lb_listener" "elastic" {
  load_balancer_arn = aws_lb.elastic.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.elastic.arn
  }
}

resource "aws_lb_target_group" "elastic" {
  name = "elastic"
  port = 5601
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "elastic" {
  target_group_arn = aws_lb_target_group.elastic.id
  target_id        = aws_instance.elastic.id
  port             = 5601
}
