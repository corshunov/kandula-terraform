# Key pair.
resource "tls_private_key" "consul" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "consul_private_key" {
  sensitive_content = tls_private_key.consul.private_key_pem
  filename          = "${local.keys_path}/consul.pem"
}

resource "null_resource" "consul_chmod_400_key" {
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.consul_private_key.filename}"
  }
}

resource "aws_key_pair" "consul" {
  key_name   = "consul"
  public_key = tls_private_key.consul.public_key_openssh
}


# Profile.
resource "aws_iam_role" "consul" {
  name               = "consul"
  assume_role_policy = file("${local.roles_path}/consul.json")
}

resource "aws_iam_policy" "describe_instances" {
  name        = "describe_instances"
  policy      = file("${local.policies_path}/describe_instances.json")
}

resource "aws_iam_policy_attachment" "consul" {
  name       = "consul"
  roles      = [aws_iam_role.consul.name]
  policy_arn = aws_iam_policy.describe_instances.arn
}

resource "aws_iam_instance_profile" "consul" {
  name  = "consul"
  role = aws_iam_role.consul.name
}


# Security group.
resource "aws_security_group" "consul" {
  name   = "consul"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "consul_ssh_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_all_inside_ingress" {
  type        = "ingress"
  protocol    = -1
  from_port   = 0
  to_port     = 0
  self        = true
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_ui_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 8500
  to_port     = 8500
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_prometheus_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 9090
  to_port     = 9090
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_http_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}

resource "aws_security_group_rule" "consul_all_egress" {
  type        = "egress"
  protocol    = -1
  from_port   = 0
  to_port     = 0
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.consul.id
}


# User data.
data "template_file" "consul" {
  count    = var.consul_count
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
    consul_version = var.consul_version
    node_exporter_version = var.node_exporter_version
    prometheus_dir = var.prometheus_dir
    config = <<EOF
      "node_name": "consul-${count.index+1}",
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


# Instance.
resource "aws_instance" "consul" {
  count                  = var.consul_count
  ami                    = data.aws_ami.ubuntu_18.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.consul.key_name
  subnet_id              = aws_subnet.private.*.id[count.index % var.az_count]
  vpc_security_group_ids = [aws_security_group.consul.id]
  user_data              = element(data.template_file.consul.*.rendered, count.index)
  iam_instance_profile   = aws_iam_instance_profile.consul.name

  tags = {
    Name = "Consul ${count.index+1}"
    consul_server = "true"
  }

  depends_on = [
    aws_route_table_association.public, aws_route_table_association.private
  ]
}


# Load balancer.
resource "aws_lb" "consul" {
  name                        = "consul"
  internal                    = false
  load_balancer_type          = "application"
  subnets                     = aws_subnet.public.*.id
  security_groups             = [aws_security_group.consul.id]
}

resource "aws_lb_listener" "consul" {
  load_balancer_arn = aws_lb.consul.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul.arn
  }
}

resource "aws_lb_target_group" "consul" {
  name = "consul"
  port = 8500
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "consul" {
  count            = length(aws_instance.consul)
  target_group_arn = aws_lb_target_group.consul.id
  target_id        = aws_instance.consul.*.id[count.index]
  port             = 8500
}
