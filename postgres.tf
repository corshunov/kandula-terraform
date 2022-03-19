# Key pair.
resource "tls_private_key" "postgres" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "postgres_private_key" {
  content = tls_private_key.postgres.private_key_pem
  filename          = "${local.keys_path}/postgres.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "postgres" {
  key_name   = "postgres"
  public_key = tls_private_key.postgres.public_key_openssh
}


# User data.
data "template_file" "consul_postgres" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
      node_exporter_version = var.node_exporter_version
      prometheus_dir = var.prometheus_dir
      config = <<EOF
       "node_name": "postgres",
       "enable_script_checks": true,
       "server": false
      EOF
  }
}

data "local_file" "postgres" {
  filename = "${local.scripts_path}/postgres.sh"
}

data "template_cloudinit_config" "postgres" {
  part {
    content = data.template_file.consul_postgres.rendered
  }

  part {
    content = data.local_file.postgres.content
  }
}


# Instance.
resource "aws_instance" "postgres" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = var.postgres_instance_type
  key_name                    = aws_key_pair.postgres.key_name
  subnet_id                   = aws_subnet.private.*.id[0]
  vpc_security_group_ids      = [aws_security_group.consul.id]
  user_data                   = data.template_cloudinit_config.postgres.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul.name

  tags = {
    Name    = "Postgres"
  }
}
