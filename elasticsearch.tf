# Key pair.
resource "tls_private_key" "elasticsearch" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "elasticsearch_private_key" {
  content = tls_private_key.elasticsearch.private_key_pem
  filename          = "${local.keys_path}/elasticsearch.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "elasticsearch" {
  key_name   = "elasticsearch"
  public_key = tls_private_key.elasticsearch.public_key_openssh
}


# User data.
data "template_file" "consul_elasticsearch" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
      node_exporter_version = var.node_exporter_version
      prometheus_dir = var.prometheus_dir
      config = <<EOF
       "node_name": "elasticsearch",
       "enable_script_checks": true,
       "server": false
      EOF
  }
}

data "local_file" "elasticsearch" {
  filename = "${local.scripts_path}/elasticsearch.sh"
}

data "template_cloudinit_config" "elasticsearch" {
  part {
    content = data.template_file.consul_elasticsearch.rendered
  }

  part {
    content = data.local_file.elasticsearch.content
  }
}


# Instance.
resource "aws_instance" "elasticsearch" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.elasticsearch_instance_type
  key_name                    = aws_key_pair.elasticsearch.key_name
  subnet_id                   = aws_subnet.private.*.id[1]
  vpc_security_group_ids      = [aws_security_group.consul.id]
  user_data                   = data.template_cloudinit_config.elasticsearch.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "ElasticSearch"
  }
}


# Load balancer.
resource "aws_lb" "elasticsearch" {
  name                        = "elasticsearch"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul.id]
}

resource "aws_lb_listener" "elasticsearch" {
  load_balancer_arn = aws_lb.elasticsearch.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.elasticsearch.arn
  }
}

resource "aws_lb_target_group" "elasticsearch" {
  name = "elasticsearch"
  port = 5601
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "elasticsearch" {
  target_group_arn = aws_lb_target_group.elasticsearch.id
  target_id        = aws_instance.elasticsearch.id
  port             = 5601
}