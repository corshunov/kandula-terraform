#!/usr/bin/env bash
set -e

apt-get update -y
apt-get install -y apt-transport-https
apt-get install -y software-properties-common wget
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -

echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list

apt-get update -y
apt-get install -y grafana

systemctl daemon-reload
systemctl enable grafana-server.service
systemctl start grafana-server.service

tee /etc/consul.d/grafana.json > /dev/null <<"EOF"
{
  "service": {
    "id": "grafana",
    "name": "grafana",
    "tags": ["grafana"],
    "port": 3000,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 3000",
        "tcp": "localhost:3000",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF

consul reload
