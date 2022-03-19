# Key pair.
resource "tls_private_key" "jenkins_agent" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "jenkins_agent_private_key" {
  sensitive_content = tls_private_key.jenkins_agent.private_key_pem
  filename          = "${local.keys_path}/jenkins_agent.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "jenkins_agent" {
  key_name   = "jenkins_agent"
  public_key = tls_private_key.jenkins_agent.public_key_openssh
}


# Profile.
resource "aws_iam_role" "jenkins_agent" {
  name               = "jenkins_agent"
  assume_role_policy = file("${local.roles_path}/jenkins_agent.json")
}

resource "aws_iam_policy" "eks" {
  name        = "eks"
  policy      = file("${local.policies_path}/eks.json")
}

resource "aws_iam_policy_attachment" "jenkins_agent" {
  name       = "jenkins_agent"
  roles      = [aws_iam_role.jenkins_agent.name]
  policy_arn = aws_iam_policy.eks.arn
}

resource "aws_iam_instance_profile" "jenkins_agent" {
  name  = "jenkins_agent"
  role = aws_iam_role.jenkins_agent.name
}


# Secutiry group.
resource "aws_security_group" "jenkins_agent" {
  name    = "jenkins_agent"
  vpc_id  = var.vpc_id
}

resource "aws_security_group_rule" "jenkins_agent_tls_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_agent.id
}

resource "aws_security_group_rule" "jenkins_agent_ssh_ingress" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_agent.id
}

resource "aws_security_group_rule" "jenkins_agent_all_egress" {
  type        = "egress"
  protocol    = "-1"
  from_port   = 0
  to_port     = 0
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_agent.id
}


# User data.
data "template_file" "consul_jenkins_agent" {
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
      node_exporter_version = var.node_exporter_version
      prometheus_dir = var.prometheus_dir
      config = <<EOF
       "node_name": "jenkins_agent",
       "enable_script_checks": true,
       "server": false
      EOF
  }
}

data "template_file" "jenkins_agent" {
  template = file("${local.scripts_path}/jenkins_agent.sh")
}

data "template_cloudinit_config" "jenkins_agent" {
  part {
    content = data.template_file.consul_jenkins_agent.rendered
  }

  part {
    content = data.template_file.jenkins_agent.rendered
  }
}


# Instance.
resource "aws_instance" "jenkins_agent" {
  count                  = var.jenkins_agent_count
  ami                    = data.aws_ami.ubuntu_18.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.jenkins_agent.key_name
  subnet_id              = aws_subnet.private.*.id[count.index % var.az_count]
  vpc_security_group_ids = [aws_security_group.jenkins_agent.id]
  user_data              = data.template_cloudinit_config.jenkins_agent.rendered
  iam_instance_profile   = aws_iam_instance_profile.jenkins_agent.name

  tags = {
    Name = "Jenkins Agent ${count.index+1}"
  }
}
