#!/usr/bin/env bash
set -e

apt-get update -y
apt-get install -y apt-transport-https ca-certificates wget

wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -

echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list

apt-get update -y
apt-get install -y kibana

tee -a /etc/kibana/kibana.yml > /dev/null <<EOF
server.host: 0.0.0.0
elasticsearch.hosts:
  - http://elasticsearch.service.consul:9200
EOF

/usr/share/kibana/bin/kibana-plugin install "https://github.com/pjhampton/kibana-prometheus-exporter/releases/download/7.17.1/kibanaPrometheusExporter-7.17.1.zip"

systemctl enable kibana.service
systemctl start kibana.service

tee /etc/consul.d/kibana.json > /dev/null <<EOF
{
  "service": {
    "id": "kibana",
    "name": "kibana",
    "tags": ["kibana"],
    "port": 5601,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 5601",
        "tcp": "localhost:5601",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF

consul reload
