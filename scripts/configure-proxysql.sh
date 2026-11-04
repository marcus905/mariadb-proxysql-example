#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Configuring ProxySQL Galera hostgroups through the Admin SQL interface..."
for i in $(seq 1 60); do
  if docker compose exec -T galera1 mariadb --protocol=tcp -hproxysql -P6032 -uradmin -pradminpass -Nse 'SELECT 1' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker compose exec -T galera1 mariadb --protocol=tcp -hproxysql -P6032 -uradmin -pradminpass <<'SQL'
DELETE FROM mysql_galera_hostgroups WHERE writer_hostgroup=10;
INSERT INTO mysql_galera_hostgroups
(writer_hostgroup,backup_writer_hostgroup,reader_hostgroup,offline_hostgroup,active,max_writers,writer_is_also_reader,max_transactions_behind)
VALUES (10,20,30,40,1,1,1,100);
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
SQL
echo "ProxySQL Galera hostgroups configured."
