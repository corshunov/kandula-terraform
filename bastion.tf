# Key pair.
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "bastion_private_key" {
  content = tls_private_key.bastion.private_key_pem
  filename          = "${local.keys_path}/bastion.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "bastion" {
  key_name   = "bastion"
  public_key = tls_private_key.bastion.public_key_openssh
}


# Security group.
resource "aws_security_group" "bastion" {
  name        = "bastion"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "bastion_ssh_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["${data.http.local_ip.body}/32"]
  security_group_id = aws_security_group.bastion.id
}


# User data.
data "template_file" "consul_bastion" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
      node_exporter_version = var.node_exporter_version
      prometheus_dir = var.prometheus_dir
      config = <<EOF
       "node_name": "bastion",
       "enable_script_checks": true,
       "server": false
      EOF
  }
}

data "local_file" "bastion" {
  filename = "${local.scripts_path}/bastion.sh"
}

data "template_cloudinit_config" "bastion" {
  part {
    content = data.template_file.consul_bastion.rendered
  }

  part {
    content = data.local_file.bastion.content
  }
}


# Instance.
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.bastion_instance_type
  key_name                    = aws_key_pair.bastion.key_name
  subnet_id                   = aws_subnet.public.*.id[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.consul.id, aws_security_group.bastion.id]
  user_data                   = data.template_cloudinit_config.bastion.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "Bastion"
  }
}
