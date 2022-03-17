resource "tls_private_key" "bastion_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "bastion_server_private_key" {
  sensitive_content = tls_private_key.bastion_server.private_key_pem
  filename          = "${path.module}/output_files/bastion_server.pem"
}

resource "null_resource" "bastion_server_chmod_400_key" {
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.bastion_server_private_key.filename}"
  }
}

resource "aws_key_pair" "bastion_server" {
  key_name   = "bastion_server"
  public_key = tls_private_key.bastion_server.public_key_openssh
}

resource "aws_instance" "bastion_server" {
  ami                         = data.aws_ami.ubuntu_18.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.bastion_server.key_name
  subnet_id                   = aws_subnet.public.*.id[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_server.id]

  tags = {
    Name    = "Bastion Server"
  }
}

resource "aws_security_group" "bastion_server" {
  name        = "bastion_server"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "bastion_server_ssh_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["${data.http.local_ip.body}/32"]
  security_group_id = aws_security_group.bastion_server.id
}

resource "aws_security_group_rule" "bastion_server_all_egress" {
  type        = "egress"
  protocol    = -1
  from_port   = 0
  to_port     = 0
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion_server.id
}
