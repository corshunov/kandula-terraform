#!/usr/bin/env bash
set -e

# elasticsearch
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-oss-7.10.2-amd64.deb
dpkg -i elasticsearch-*.deb
systemctl enable elasticsearch
systemctl start elasticsearch

# kibana
wget https://artifacts.elastic.co/downloads/kibana/kibana-oss-7.10.2-amd64.deb
dpkg -i kibana-*.deb
echo 'server.host: "0.0.0.0"' > /etc/kibana/kibana.yml
systemctl enable kibana
systemctl start kibana

# filebeat
wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-7.11.0-amd64.deb
dpkg -i filebeat-*.deb

tee /etc/consul.d/elasticsearch.json > /dev/null <<"EOF"
{
  "service": {
    "id": "elasticsearch",
    "name": "elasticsearch",
    "tags": ["elasticsearch"],
    "port": 9300,
    "checks": [
      {
        "id": "tcp1",
        "name": "TCP on port 9300",
        "tcp": "localhost:9300",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF

tee /etc/consul.d/kibana.json > /dev/null <<"EOF"
{
  "service": {
    "id": "kibana",
    "name": "kibana",
    "tags": ["kibana"],
    "port": 5601,
    "checks": [
      {
        "id": "tcp2",
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
