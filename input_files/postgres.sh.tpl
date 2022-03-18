#!/usr/bin/env bash
set -e

apt-get update
wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

echo "deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

apt-get update
apt-get install -y postgresql-14

systemctl daemon-reload
systemctl enable postgresql.service
systemctl start postgresql.service

mkdir /opt/postgres_exporter
cd /opt/postgres_exporter

wget https://github.com/wrouesnel/postgres_exporter/releases/download/v0.5.1/postgres_exporter_v0.5.1_linux-amd64.tar.gz

tar -xzvf postgres_exporter_v0.5.1_linux-amd64.tar.gz

cd postgres_exporter_v0.5.1_linux-amd64
cp postgres_exporter /usr/local/bin

tee /opt/postgres_exporter/postgres_exporter.env > /dev/null <<EOF
DATA_SOURCE_NAME="postgresql://postgres:postgres@localhost:5432/?sslmode=disable"
EOF

tee /etc/systemd/system/postgres_exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus exporter for Postgresql
Wants=network-online.target
After=network-online.target
[Service]
User=postgres
Group=postgres
WorkingDirectory=/opt/postgres_exporter
EnvironmentFile=/opt/postgres_exporter/postgres_exporter.env
ExecStart=/usr/local/bin/postgres_exporter --web.listen-address=:9187 --web.telemetry-path=/metrics
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start postgres_exporter
systemctl enable postgres_exporter


### add postgres service to consul
tee /etc/consul.d/postgres.json > /dev/null <<"EOF"
{
  "service": {
    "id": "postgres",
    "name": "postgres",
    "tags": ["postgres"],
    "port": 5432,
    "checks": [
      {
        "id": "tcp",
        "name": "TCP on port 5432",
        "tcp": "localhost:5432",
        "interval": "10s",
        "timeout": "1s"
      }
    ]
  }
}
EOF

consul reload
