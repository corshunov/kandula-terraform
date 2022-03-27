#!/usr/bin/env bash
set -e

apt-get update -y

apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -

echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | tee -a /etc/apt/sources.list.d/trivy.list

apt-get update -y

apt-get install -y docker.io

usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

apt-get install -y trivy

trivy image --download-db-only

apt-get install -y python3-pip

apt-get install -y kubectl awscli git openjdk-8-jdk

tee /etc/consul.d/jenkins_agent.json > /dev/null <<EOF
{
  "service": {
    "id": "jenkins_agent",
    "name": "jenkins_agent",
    "tags": ["jenkins_agent"],
    "port": 22,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 22",
        "tcp": "localhost:22",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF

consul reload
