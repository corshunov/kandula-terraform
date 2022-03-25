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
    consul_encrypt_key = var.consul_encrypt_key
    node_exporter_version = var.node_exporter_version
    prometheus_dir = var.prometheus_dir
    config = <<EOF
"node_name": "postgres",
"enable_script_checks": true,
"server": false
    EOF
  }
}

data "template_file" "postgres" {
  template = file("${local.templates_path}/postgres.sh.tpl")

  vars = {
    postgres_admin_password = var.postgres_admin_password
    postgres_kandula_password = var.postgres_kandula_password
  }
}

data "template_file" "filebeat_postgres" {
  template = file("${local.templates_path}/filebeat.sh.tpl")

  vars = {
      servname = "postgres"
  }
}

data "template_cloudinit_config" "postgres" {
  part {
    content = data.template_file.consul_postgres.rendered
  }

  part {
    content = data.template_file.postgres.rendered
  }

  part {
    content = data.template_file.filebeat_postgres.rendered
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
  iam_instance_profile        = aws_iam_instance_profile.postgres.name

  tags = {
    Name    = "Postgres"
  }

  depends_on = [
    aws_instance.consul
  ]
}
