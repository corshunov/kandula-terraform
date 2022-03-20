#!/usr/bin/env bash
set -e

tee /etc/consul.d/jenkins_main.json > /dev/null <<"EOF"
{
  "service": {
    "id": "jenkins_main",
    "name": "jenkins_main",
    "tags": ["jenkins_main"],
    "port": 8080,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 8080",
        "tcp": "localhost:8080",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF

consul reload
