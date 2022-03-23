#!/usr/bin/env bash
set -e

apt-get update -y
apt-get install -y apt-transport-https ca-certificates wget

wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -

echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list

apt-get update -y
apt-get install -y filebeat

tee /etc/filebeat/filebeat.yml > /dev/null <<EOF
filebeat.modules:
  - module: system
    syslog:
      enabled: true
    auth:
      enabled: true

filebeat.config.modules:
  path: \$${path.config}/modules.d/*.yml
  reload.enabled: false

setup.dashboards.enabled: true
setup.kibana.host: "kibana.service.consul:5601"

setup.template.name: "filebeat-${servname}"
setup.template.pattern: "filebeat-${servname}"
setup.template.settings:
  index.number_of_shards: 1

setup.ilm.enabled: false

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_cloud_metadata: ~

output.elasticsearch:
  hosts: ["elasticsearch.service.consul:9200"]
  index: "filebeat-${servname}-%%{[agent.version]}-%%{+yyyy.MM.dd}"
EOF

sed -i '/\[Service\]/ i StartLimitIntervalSec=0' /lib/systemd/system/filebeat.service
sed -i '/\[Install\]/ i RestartSec=30' /lib/systemd/system/filebeat.service
systemctl daemon-reload
systemctl enable filebeat.service
systemctl start filebeat.service
