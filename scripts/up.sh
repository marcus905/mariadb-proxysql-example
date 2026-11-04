#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if docker compose ps --status running --services | grep -Eq '^galera[123]$'; then
  echo "Galera is running. Use docker compose up -d for an existing cluster."
  exit 1
fi
if docker volume ls --format '{{.Name}}' | grep -qE '^mariadb-galera-proxysql_galera[123]_data$'; then
  echo "Existing Galera data volumes detected. Refusing automatic bootstrap."
  echo "For a complete disposable reset: docker compose down -v, then ./scripts/up.sh"
  echo "For data recovery, follow the README; do not bootstrap blindly."
  exit 1
fi
echo "Starting first node as new cluster..."
GALERA_BOOTSTRAP=1 docker compose up -d --no-deps galera1
echo "Waiting for first node to become PRIMARY..."
for i in $(seq 1 90); do
  if docker compose exec -T galera1 mariadb -uroot -p"${MARIADB_ROOT_PASSWORD:-rootpass}" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_ready'" 2>/dev/null | grep -q $'wsrep_ready\tON'; then break; fi
  sleep 2
done
docker compose exec -T galera1 mariadb -uroot -p"${MARIADB_ROOT_PASSWORD:-rootpass}" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_ready'" | grep -q $'wsrep_ready\tON' || { echo "Bootstrap failed"; exit 1; }
echo "Joining remaining nodes..."
docker compose up -d --no-deps galera2 galera3
for i in $(seq 1 120); do
  if docker compose exec -T galera1 mariadb -uroot -p"${MARIADB_ROOT_PASSWORD:-rootpass}" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | grep -q $'wsrep_cluster_size\t3'; then break; fi
  sleep 2
done
docker compose exec -T galera1 mariadb -uroot -p"${MARIADB_ROOT_PASSWORD:-rootpass}" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" | grep -q $'wsrep_cluster_size\t3' || { echo "Nodes failed to join"; exit 1; }
echo "Removing bootstrap flag from node1's configuration (recreates node1 after peers are ready)..."
GALERA_BOOTSTRAP=0 docker compose up -d --no-deps --force-recreate galera1
echo "Starting ProxySQL..."
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
