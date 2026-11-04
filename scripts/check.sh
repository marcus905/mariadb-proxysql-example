#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for node in galera1 galera2 galera3; do
  echo "=== $node ==="
  docker compose exec -T "$node" mariadb -uroot -p"${MARIADB_ROOT_PASSWORD:-rootpass}" -e "SHOW GLOBAL STATUS WHERE Variable_name IN ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready');"
done
echo "=== ProxySQL frontend (through host-published 6033) ==="
echo "Use a local MySQL/MariaDB CLI: mariadb -h127.0.0.1 -P6033 -ulabuser -plabpass --protocol=tcp -e 'SELECT @@hostname;'"
echo "=== ProxySQL admin (local host only, 6032) ==="
echo "Use: mariadb -h127.0.0.1 -P6032 -uradmin -pradminpass --protocol=tcp -e 'SELECT hostgroup_id,hostname,status FROM runtime_mysql_servers;'"
