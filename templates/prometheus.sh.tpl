#!/usr/bin/env bash
set -e

### Install Prometheus Collector
wget https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/prometheus-${prometheus_version}.linux-amd64.tar.gz -O /tmp/prometheus.tgz
mkdir -p ${prometheus_dir}
tar zxf /tmp/prometheus.tgz -C ${prometheus_dir}

# Create Prometheus configuration
mkdir -p /etc/prometheus
tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
scrape_configs:
  - job_name: 'nodes'
    consul_sd_configs:
    - server: 'localhost:8500'
    relabel_configs:
    - source_labels: ['__address__']
      target_label: '__address__'
      regex: '(.*):(.*)'
      replacement: '\$${1}:9100'
    - source_labels: ['__meta_consul_node']
      target_label: 'instance'

  - job_name: 'prometheus'
    consul_sd_configs:
    - server: 'localhost:8500'
      services:
      - prometheus
    relabel_configs:
    - source_labels: ['__address__']
      target_label: '__address__'
      regex: '(.*):(.*)'
      replacement: '\$${1}:9090'
    - source_labels: ['__meta_consul_node']
      target_label: 'instance'

  - job_name: 'consul'
    metrics_path: '/v1/agent/metrics'
    params:
      format: ['prometheus']
    consul_sd_configs:
    - server: 'localhost:8500'
      services:
      - consul
    relabel_configs:
    - source_labels: ['__address__']
      target_label: '__address__'
      regex: '(.*):(.*)'
      replacement: '\$${1}:8500'
    - source_labels: ['__meta_consul_node']
      target_label: 'instance'

  - job_name: 'grafana'
    consul_sd_configs:
    - server: 'localhost:8500'
      services:
      - grafana
    relabel_configs:
    - source_labels: ['__address__']
      target_label: '__address__'
      regex: '(.*):(.*)'
      replacement: '\$${1}:3000'
    - source_labels: ['__meta_consul_node']
      target_label: 'instance'

  - job_name: 'postgres'
    consul_sd_configs:
    - server: 'localhost:8500'
      services:
      - postgres
    relabel_configs:
    - source_labels: ['__address__']
      target_label: '__address__'
      regex: '(.*):(.*)'
      replacement: '\$${1}:9187'
    - source_labels: ['__meta_consul_node']
      target_label: 'instance'

  - job_name: 'elasticsearch'
    scrape_timeout: 30s
    consul_sd_configs:
    - server: 'localhost:8500'
      services:
      - elasticsearch
    relabel_configs:
    - source_labels: ['__address__']
      target_label: '__address__'
      regex: '(.*):(.*)'
      replacement: '\$${1}:9114'
    - source_labels: ['__meta_consul_node']
      target_label: 'instance'

  - job_name: 'kibana'
    metrics_path: '/_prometheus/metrics'
    consul_sd_configs:
    - server: 'localhost:8500'
      services:
      - kibana
    relabel_configs:
    - source_labels: ['__address__']
      target_label: '__address__'
      regex: '(.*):(.*)'
      replacement: '\$${1}:5601'
    - source_labels: ['__meta_consul_node']
      target_label: 'instance'

  - job_name: 'jenkins_main'
    metrics_path: '/prometheus'
    consul_sd_configs:
    - server: 'localhost:8500'
      services:
      - jenkins_main
    relabel_configs:
    - source_labels: ['__address__']
      target_label: '__address__'
      regex: '(.*):(.*)'
      replacement: '\$${1}:8080'
    - source_labels: ['__meta_consul_node']
      target_label: 'instance'
EOF

# Configure promcol service
tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Collector
Requires=network-online.target
After=network.target
[Service]
ExecStart=${prometheus_dir}/prometheus-${prometheus_version}.linux-amd64/prometheus --config.file=/etc/prometheus/prometheus.yml
ExecReload=/bin/kill -s HUP \$MAINPID
KillSignal=SIGINT
TimeoutStopSec=5
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus.service
systemctl start prometheus.service

tee /etc/consul.d/prometheus.json > /dev/null <<EOF
{
  "service": {
    "id": "prometheus",
    "name": "prometheus",
    "tags": ["prometheus"],
    "port": 9090,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 9090",
        "tcp": "localhost:9090",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF

consul reload
