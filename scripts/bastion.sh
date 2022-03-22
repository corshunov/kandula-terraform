#!/usr/bin/env bash
set -e

apt-get update -y

tee /etc/consul.d/bastion.json > /dev/null <<EOF
{
  "service": {
    "id": "bastion",
    "name": "bastion",
    "tags": ["bastion"],
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
