resource "tls_private_key" "consul_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "consul_server_private_key" {
  sensitive_content = tls_private_key.consul_server.private_key_pem
  filename          = "${path.module}/output_files/consul_server.pem"
}

resource "null_resource" "consul_server_chmod_400_key" {
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.consul_server_private_key.filename}"
  }
}

resource "aws_key_pair" "consul_server" {
  key_name   = "consul_server"
  public_key = tls_private_key.consul_server.public_key_openssh
}

data "template_file" "consul_server" {
  count    = var.consul_server_count
  template = file("${path.module}/input_files/consul.sh.tpl")

  vars = {
    consul_version = var.consul_version
    node_exporter_version = var.node_exporter_version
    prometheus_dir = var.prometheus_dir
    config = <<EOF
      "node_name": "consul-server-${count.index+1}",
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

resource "aws_iam_role" "consul_server" {
  name               = "consul_server"
  assume_role_policy = file("${path.module}/input_files/consul_server_assume_role.json")
}

resource "aws_iam_policy" "consul_server" {
  name        = "consul_server"
  policy      = file("${path.module}/input_files/consul_server_describe_instances.json")
}

resource "aws_iam_policy_attachment" "consul_server" {
  name       = "consul_server"
  roles      = [aws_iam_role.consul_server.name]
  policy_arn = aws_iam_policy.consul_server.arn
}

resource "aws_iam_instance_profile" "consul_server" {
  name  = "consul_server"
  role = aws_iam_role.consul_server.name
}

resource "aws_instance" "consul_server" {
  count                  = var.consul_server_count
  ami                    = data.aws_ami.ubuntu_18.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.consul_server.key_name
  subnet_id              = aws_subnet.private.*.id[count.index % 2]
  vpc_security_group_ids = [aws_security_group.consul_server.id]
  user_data              = element(data.template_file.consul_server.*.rendered, count.index)
  iam_instance_profile   = aws_iam_instance_profile.consul_server.name

  tags = {
    Name = "Consul Server ${count.index+1}"
    consul_server = "true"
  }

  depends_on = [
    aws_route_table_association.public, aws_route_table_association.private
  ]
}

resource "aws_security_group" "consul_server" {
  name   = "consul_server"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "consul_server_ssh_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul_server.id
}

resource "aws_security_group_rule" "consul_server_all_inside_ingress" {
  type        = "ingress"
  protocol    = -1
  from_port   = 0
  to_port     = 0
  self        = true
  security_group_id = aws_security_group.consul_server.id
}

resource "aws_security_group_rule" "consul_server_ui_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 8500
  to_port     = 8500
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul_server.id
}

resource "aws_security_group_rule" "consul_server_prom_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 9090
  to_port     = 9090
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul_server.id
}

resource "aws_security_group_rule" "consul_server_http_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul_server.id
}

resource "aws_security_group_rule" "consul_server_all_egress" {
  type        = "egress"
  protocol    = -1
  from_port   = 0
  to_port     = 0
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul_server.id
}

resource "aws_lb" "consul_server" {
  name                        = "consul-lb"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul_server.id]
}

resource "aws_lb_listener" "consul_server" {
  load_balancer_arn = aws_lb.consul_server.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul_server.arn
  }
}

resource "aws_lb_target_group" "consul_server" {
  name = "consul-server"
  port = 8500
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "consul_server" {
  count            = length(aws_instance.consul_server)
  target_group_arn = aws_lb_target_group.consul_server.id
  target_id        = aws_instance.consul_server.*.id[count.index]
  port             = 8500
}
