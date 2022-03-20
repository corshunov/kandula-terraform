# Key pair.
resource "tls_private_key" "jenkins_main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "jenkins_main_private_key" {
  content = tls_private_key.jenkins_main.private_key_pem
  filename          = "${local.keys_path}/jenkins_main.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "jenkins_main" {
  key_name   = "jenkins_main"
  public_key = tls_private_key.jenkins_main.public_key_openssh
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

data "local_file" "jenkins_main" {
  filename = "${local.scripts_path}/jenkins_main.sh"
}

data "template_cloudinit_config" "jenkins_main" {
  part {
    content = data.template_file.consul_jenkins_main.rendered
  }

  part {
    content = data.local_file.jenkins_main.content
  }
}


# Instance.
resource "aws_instance" "jenkins_main" {
  ami                         = data.aws_ami.jenkins_main.id
  #ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.jenkins_main_instance_type
  key_name                    = aws_key_pair.jenkins_main.key_name
  subnet_id                   = aws_subnet.private.*.id[0]
  vpc_security_group_ids      = [aws_security_group.consul.id]
  user_data                   = data.template_cloudinit_config.jenkins_main.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "Jenkins Main"
  }
}


# Load balancer.
resource "aws_lb" "jenkins_main" {
  name                        = "jenkins-main"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul.id]
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
  name = "jenkins-main"
  port = 8080
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
  port             = 8080
}
