resource "tls_private_key" "postgres_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "postgres_server_private_key" {
  sensitive_content = tls_private_key.postgres_server.private_key_pem
  filename          = "${path.module}/output_files/postgres_server.pem"
}

resource "null_resource" "postgres_server_chmod_400_key" {
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.postgres_server_private_key.filename}"
  }
}

resource "aws_key_pair" "postgres_server" {
  key_name   = "postgres_server"
  public_key = tls_private_key.postgres_server.public_key_openssh
}

data "template_file" "consul_postgres" {
  template = file("${path.module}/input_files/consul.sh.tpl")

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

data "template_file" "postgres" {
  template = file("${path.module}/input_files/postgres.sh.tpl")
}

data "template_cloudinit_config" "postgres" {
  part {
    content = data.template_file.consul_postgres.rendered
  }

  part {
    content = data.template_file.postgres.rendered
  }
}

resource "aws_instance" "postgres_server" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.postgres_server.key_name
  subnet_id                   = aws_subnet.private.*.id[0]
  vpc_security_group_ids      = [aws_security_group.consul_server.id]
  user_data                   = data.template_cloudinit_config.postgres.rendered
  iam_instance_profile        = aws_iam_instance_profile.consul_server.name

  tags = {
    Name    = "Postgres Server"
  }
}
