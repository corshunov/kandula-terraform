# Key pair.
resource "tls_private_key" "jenkins_main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "jenkins_main_private_key" {
  sensitive_content = tls_private_key.jenkins_main.private_key_pem
  filename          = "${local.keys_path}/jenkins_main.pem"
}

resource "null_resource" "jenkins_main_chmod_400_key" {
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.jenkins_main_private_key.filename}"
  }
}

resource "aws_key_pair" "jenkins_main" {
  key_name   = "jenkins_main"
  public_key = tls_private_key.jenkins_main.public_key_openssh
}


# Security group.
resource "aws_security_group" "jenkins_main" {
  name    = "jenkins_main"
  vpc_id  = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "jenkins_main_tls_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_main.id
}

resource "aws_security_group_rule" "jenkins_main_http_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_main.id
}

resource "aws_security_group_rule" "jenkins_main_ssh_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_main.id
}

resource "aws_security_group_rule" "jenkins_main_all_egress" {
  type        = "egress"
  protocol    = "-1"
  from_port   = 0
  to_port     = 0
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_main.id
}


# User data.
data "template_file" "consul_jenkins_main" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
      node_exporter_version = var.node_exporter_version
      prometheus_dir = var.prometheus_dir
      config = <<EOF
       "node_name": "jenkins_main",
       "enable_script_checks": true,
       "server": false
      EOF
  }
}

data "template_file" "jenkins_main" {
  template = file("${local.scripts_path}/jenkins_main.sh")
}

data "template_cloudinit_config" "jenkins_main" {
  part {
    content = data.template_file.consul_jenkins_main.rendered
  }

  part {
    content = data.template_file.jenkins_main.rendered
  }
}


# Instance.
resource "aws_instance" "jenkins_main" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.jenkins_main.key_name
  subnet_id                   = aws_subnet.private.*.id[0]
  vpc_security_group_ids      = [aws_security_group.jenkins_main.id]
  user_data                   = data.template_cloudinit_config.jenkins_main.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "Jenkins Main"
  }
}


# Load balancer.
resource "aws_lb" "jenkins_main" {
  name                        = "jenkins_main"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.jenkins_main.id]
}

resource "aws_lb_listener" "jenkins_main" {
  load_balancer_arn = aws_lb.jenkins_main.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins_main.arn
  }
}

resource "aws_lb_target_group" "jenkins_main" {
  name = "jenkins_main"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins_main.id
  target_id        = aws_instance.jenkins_main.id
  port             = 80
}
