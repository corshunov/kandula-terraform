resource "tls_private_key" "prometheus_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "prometheus_server_private_key" {
  sensitive_content = tls_private_key.prometheus_server.private_key_pem
  filename          = "${path.module}/output_files/prometheus_server.pem"
}

resource "null_resource" "prometheus_server_chmod_400_key" {
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.prometheus_server_private_key.filename}"
  }
}

resource "aws_key_pair" "prometheus_server" {
  key_name   = "prometheus_server"
  public_key = tls_private_key.prometheus_server.public_key_openssh
}

data "template_file" "consul_prometheus" {
  template = file("${path.module}/input_files/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
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
  template = file("${path.module}/input_files/prometheus.sh.tpl")

  vars = {
      prometheus_version = var.prometheus_version
      prometheus_conf_dir = var.prometheus_conf_dir
      prometheus_dir = var.prometheus_dir
  }
}

data "template_cloudinit_config" "prometheus" {
  part {
    content = data.template_file.consul_prometheus.rendered

  }
  part {
    content = data.template_file.prometheus.rendered
  }
}

resource "aws_instance" "prometheus_server" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.prometheus_server.key_name
  subnet_id                   = aws_subnet.private.*.id[1]
  vpc_security_group_ids      = [aws_security_group.consul_server.id]
  user_data                   = data.template_cloudinit_config.prometheus.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul_server.name

  tags = {
    Name    = "Prometheus Server"
  }
}

resource "aws_lb" "prometheus_server" {
  name                        = "prometheus-lb"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul_server.id]
}

resource "aws_lb_listener" "prometheus_server" {
  load_balancer_arn = aws_lb.prometheus_server.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus_server.arn
  }
}

resource "aws_lb_target_group" "prometheus_server" {
  name = "prometheus-server"
  port = 9090
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "prometheus_server" {
  target_group_arn = aws_lb_target_group.prometheus_server.id
  target_id        = aws_instance.prometheus_server.id
  port             = 9090
}
