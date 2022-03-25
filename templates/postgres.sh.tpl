#!/usr/bin/env bash
set -e

apt-get update -y
wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

echo "deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

apt-get update -y
apt-get install -y postgresql-14

echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/14/main/pg_hba.conf
sed -i "/# - Connection Settings -/ a listen_addresses = '*'" /etc/postgresql/14/main/postgresql.conf
systemctl daemon-reload
systemctl enable postgresql.service
systemctl start postgresql.service

cd /var/lib/postgresql
sudo -u postgres -s <<EOF1
psql -c "ALTER ROLE postgres WITH PASSWORD '${postgres_admin_password}'"
psql -c "CREATE USER kandula WITH ENCRYPTED PASSWORD '${postgres_kandula_password}'"
psql -c "CREATE DATABASE kandula"
psql <<EOF2 kandula
CREATE TABLE plan_shutdown (
    instance_id       VARCHAR(50),
    time              TIME
);

GRANT SELECT, INSERT, UPDATE, DELETE ON plan_shutdown TO kandula;

CREATE TABLE done_shutdown (
    id                SERIAL PRIMARY KEY,
    timestamp         TIMESTAMP NOT NULL DEFAULT current_timestamp,
    instance_id       VARCHAR(50)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON done_shutdown TO kandula;
GRANT USAGE, SELECT ON SEQUENCE done_shutdown_id_seq TO kandula;
EOF2
EOF1

systemctl restart postgresql.service

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

apt-get install -y python3-pip libpq-dev jq
pip3 install pytz boto3 psycopg2-binary
export AWS_DEFAULT_REGION=`curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`

tee /home/ubuntu/shutdown_job.py > /dev/null <<EOF
import base64
from datetime import datetime
import requests

from boto3 import client
import psycopg2
import pytz


ec2_client = client('ec2')


def check_shutdown():
    try:
        r = requests.get('http://localhost:8500/v1/kv/postgres_kandula_password')
    except:
        return

    if r.status_code == 200:
        password_bytes = r.json()[0]["Value"]
        password = base64.b64decode(password_bytes).decode("utf-8")
    else:
        return

    try:
        conn = psycopg2.connect(
                        host="localhost",
                        database="kandula",
                        user="kandula",
                        password=password
        )
    except:
        return

    query = "SELECT * FROM plan_shutdown;"

    with conn:
        with conn.cursor() as cur:
            cur.execute(query)
            data = cur.fetchall()

    tz = pytz.timezone('Asia/Jerusalem')
    dt = datetime.now(tz)

    for instance_id, time in data:
        if time.hour == dt.hour:
            query = f"DELETE FROM plan_shutdown WHERE instance_id = '{instance_id}';"

            with conn:
                with conn.cursor() as cur:
                    cur.execute(query)

            try:
                ec2_client.terminate_instances(InstanceIds=[instance_id])
            except:
                continue

            query = f"INSERT INTO done_shutdown(instance_id) values('{instance_id}');"

            with conn:
                with conn.cursor() as cur:
                    cur.execute(query)


if __name__ == "__main__":
    check_shutdown()
EOF

echo "0 * * * * python3 /home/ubuntu/shutdown_job.py" > job
crontab -u ubuntu job
rm job

tee /etc/consul.d/postgres.json > /dev/null <<EOF
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
