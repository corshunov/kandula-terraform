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

mkdir -p /home/ubuntu/jenkins_home
chown -R 1000:1000 /home/ubuntu/jenkins_home

docker run -d --restart=always -p 80:8080 -p 50000:50000 \
           -v /home/ubuntu/jenkins_home:/var/jenkins_home \
           -v /var/run/docker.sock:/var/run/docker.sock \
           --env JAVA_OPTS='-Djenkins.install.runSetupWizard=false' \
           jenkins/jenkins

tee /etc/consul.d/jenkins_main.json > /dev/null <<"EOF"
{
  "service": {
    "id": "jenkins_main",
    "name": "jenkins_main",
    "tags": ["jenkins_main"],
    "port": 80,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 80",
        "tcp": "localhost:80",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF
