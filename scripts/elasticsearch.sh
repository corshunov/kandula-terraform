#!/usr/bin/env bash
set -e

apt-get update -y
apt-get install -y apt-transport-https ca-certificates wget

wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -

echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list

apt-get update -y
apt-get install -y elasticsearch

tee -a /etc/elasticsearch/elasticsearch.yml > /dev/null <<EOF
network.host: 0.0.0.0
network.bind_host: 0.0.0.0
network.publish_host: 0.0.0.0
discovery.seed_hosts: ["0.0.0.0", "[::0]"]
node.name: master
cluster.initial_master_nodes: ["master"]
EOF

systemctl enable elasticsearch.service
systemctl start elasticsearch.service

wget "https://github.com/prometheus-community/elasticsearch_exporter/releases/download/v1.3.0/elasticsearch_exporter-1.3.0.linux-amd64.tar.gz"
tar xvf elasticsearch_exporter-1.3.0.linux-amd64.tar.gz
cp elasticsearch_exporter-1.3.0.linux-amd64/elasticsearch_exporter /usr/local/bin/es_exporter

tee /etc/systemd/system/es_exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus ES_exporter
After=local-fs.target network-online.target network.target
Wants=local-fs.target network-online.target network.target

[Service]
User=root
Nice=10
ExecStart=/usr/local/bin/es_exporter --es.uri=http://localhost:9200 --es.all --es.indices --es.timeout 20s
ExecStop=/usr/bin/killall es_exporter

[Install]
WantedBy=default.target
EOF

systemctl enable es_exporter.service
systemctl start es_exporter.service

tee /etc/consul.d/elasticsearch.json > /dev/null <<EOF
{
  "service": {
    "id": "elasticsearch",
    "name": "elasticsearch",
    "tags": ["elasticsearch"],
    "port": 9200,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 9200",
        "tcp": "localhost:9200",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF

consul reload
