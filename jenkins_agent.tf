# Key pair.
resource "tls_private_key" "jenkins_agent" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "jenkins_agent_private_key" {
  content = tls_private_key.jenkins_agent.private_key_pem
  filename          = "${local.keys_path}/jenkins_agent.pem"
  file_permission   = "0400"
}

resource "aws_key_pair" "jenkins_agent" {
  key_name   = "jenkins_agent"
  public_key = tls_private_key.jenkins_agent.public_key_openssh
}


# User data.
data "template_file" "consul_jenkins_agent" {
  count    = var.jenkins_agent_count
  template = file("${local.templates_path}/consul.sh.tpl")

  vars = {
      consul_version = var.consul_version
      node_exporter_version = var.node_exporter_version
      prometheus_dir = var.prometheus_dir
      config = <<EOF
       "node_name": "jenkins-agent-${count.index+1}",
       "enable_script_checks": true,
       "server": false
      EOF
  }
}

data "local_file" "jenkins_agent" {
  count    = var.jenkins_agent_count
  filename = "${local.scripts_path}/jenkins_agent.sh"
}

data "template_cloudinit_config" "jenkins_agent" {
  count    = var.jenkins_agent_count
  part {
    content = data.template_file.consul_jenkins_agent.*.rendered[count.index]
  }

  part {
    content = data.local_file.jenkins_agent.*.content[count.index]
  }
}


# Instance.
resource "aws_instance" "jenkins_agent" {
  count                  = var.jenkins_agent_count
  ami                    = data.aws_ami.ubuntu_18.id
  instance_type          = var.jenkins_agent_instance_type
  key_name               = aws_key_pair.jenkins_agent.key_name
  subnet_id              = aws_subnet.private.*.id[count.index % var.az_count]
  vpc_security_group_ids = [aws_security_group.consul.id]
  user_data              = data.template_cloudinit_config.jenkins_agent.*.rendered[count.index]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_agent.name

  tags = {
    Name = "Jenkins Agent ${count.index+1}"
  }
}
