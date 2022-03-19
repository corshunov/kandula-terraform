#!/usr/bin/env bash
set -e

apt-get update -y

apt-get install -y apt-transport-https ca-certificates curl

curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y

apt-get install -y docker.io

usermod -aG docker ubuntu
systemctl start docker
systemctl enable docker

apt-get install -y kubectl awscli git openjdk-8-jdk

tee /etc/consul.d/jenkins_agent.json > /dev/null <<"EOF"
{
  "service": {
    "id": "jenkins_agent",
    "name": "jenkins_agent",
    "tags": ["jenkins_agent"],
    "port": 443,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 443",
        "tcp": "localhost:443",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF
