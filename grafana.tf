resource "tls_private_key" "grafana_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "grafana_server_private_key" {
  sensitive_content = tls_private_key.grafana_server.private_key_pem
  filename          = "${path.module}/output_files/grafana_server.pem"
}

resource "null_resource" "grafana_server_chmod_400_key" {
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.grafana_server_private_key.filename}"
  }
}

resource "aws_key_pair" "grafana_server" {
  key_name   = "grafana_server"
  public_key = tls_private_key.grafana_server.public_key_openssh
}

data "template_file" "consul_grafana" {
  template = file("${path.module}/input_files/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
      node_exporter_version = var.node_exporter_version
      prometheus_dir = var.prometheus_dir
      config = <<EOF
       "node_name": "grafana",
       "enable_script_checks": true,
       "server": false
      EOF
  }
}

data "template_file" "grafana" {
  template = file("${path.module}/input_files/grafana.sh.tpl")
}

data "template_cloudinit_config" "grafana" {
  part {
    content = data.template_file.consul_grafana.rendered
  }

  part {
    content = data.template_file.grafana.rendered
  }
}

resource "aws_instance" "grafana_server" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.grafana_server.key_name
  subnet_id                   = aws_subnet.private.*.id[1]
  vpc_security_group_ids      = [aws_security_group.consul_server.id]
  user_data                   = data.template_cloudinit_config.grafana.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul_server.name

  tags = {
    Name    = "Grafana Server"
  }
}

resource "aws_lb" "grafana_server" {
  name                        = "grafana-lb"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul_server.id]
}

resource "aws_lb_listener" "grafana_server" {
  load_balancer_arn = aws_lb.grafana_server.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana_server.arn
  }
}

resource "aws_lb_target_group" "grafana_server" {
  name = "grafana-server"
  port = 3000
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "grafana_server" {
  target_group_arn = aws_lb_target_group.grafana_server.id
  target_id        = aws_instance.grafana_server.id
  port             = 3000
}
