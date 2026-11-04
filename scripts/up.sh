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
# Membership alone is not enough: joining peers may still be receiving SST.
galera_node_synced() {
  local node="$1"
  local state
  state="$(docker compose exec -T "$node" mariadb -uroot -p"${MARIADB_ROOT_PASSWORD:-rootpass}" -Nse "SHOW GLOBAL STATUS WHERE Variable_name IN ('wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready');" 2>/dev/null)" || return 1
  grep -Fq 
GALERA_BOOTSTRAP=0 docker compose up -d --no-deps --force-recreate galera1
echo "Waiting for galera1 to rejoin the existing Primary Component..."
rejoined=0
for i in $(seq 1 120); do
  if galera_node_synced galera1 &&
     docker compose exec -T galera1 mariadb -uroot -p"${MARIADB_ROOT_PASSWORD:-rootpass}" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | grep -Fq 
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
wsrep_cluster_status\tPrimary' <<<"$state" &&
  grep -Fq 
GALERA_BOOTSTRAP=0 docker compose up -d --no-deps --force-recreate galera1
echo "Starting ProxySQL..."
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
wsrep_local_state_comment\tSynced' <<<"$state" &&
  grep -Fq 
GALERA_BOOTSTRAP=0 docker compose up -d --no-deps --force-recreate galera1
echo "Starting ProxySQL..."
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
wsrep_ready\tON' <<<"$state"
}
echo "Waiting for every node to be Synced before recreating galera1..."
all_synced=0
for i in $(seq 1 120); do
  if galera_node_synced galera1 && galera_node_synced galera2 && galera_node_synced galera3; then
    all_synced=1
    break
  fi
  sleep 2
done
if [ "$all_synced" -ne 1 ]; then
  echo "Nodes did not become Synced. Inspect: docker compose logs --tail=150 galera1 galera2 galera3" >&2
  exit 1
fi
echo "Removing bootstrap flag from node1's configuration (recreates node1 after peers are ready)..."
GALERA_BOOTSTRAP=0 docker compose up -d --no-deps --force-recreate galera1
echo "Starting ProxySQL..."
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
wsrep_cluster_size\t3'; then
    rejoined=1
    break
  fi
  sleep 2
done
if [ "$rejoined" -ne 1 ]; then
  echo "galera1 did not rejoin. Inspect: docker compose logs --tail=150 galera1 galera2 galera3" >&2
  exit 1
fi
echo "Starting ProxySQL..."
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
wsrep_cluster_status\tPrimary' <<<"$state" &&
  grep -Fq 
GALERA_BOOTSTRAP=0 docker compose up -d --no-deps --force-recreate galera1
echo "Starting ProxySQL..."
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
wsrep_local_state_comment\tSynced' <<<"$state" &&
  grep -Fq 
GALERA_BOOTSTRAP=0 docker compose up -d --no-deps --force-recreate galera1
echo "Starting ProxySQL..."
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
wsrep_ready\tON' <<<"$state"
}
echo "Waiting for every node to be Synced before recreating galera1..."
all_synced=0
for i in $(seq 1 120); do
  if galera_node_synced galera1 && galera_node_synced galera2 && galera_node_synced galera3; then
    all_synced=1
    break
  fi
  sleep 2
done
if [ "$all_synced" -ne 1 ]; then
  echo "Nodes did not become Synced. Inspect: docker compose logs --tail=150 galera1 galera2 galera3" >&2
  exit 1
fi
echo "Removing bootstrap flag from node1's configuration (recreates node1 after peers are ready)..."
GALERA_BOOTSTRAP=0 docker compose up -d --no-deps --force-recreate galera1
echo "Starting ProxySQL..."
docker compose up -d --no-deps proxysql
bash scripts/configure-proxysql.sh
echo "Run bash scripts/check.sh to verify the cluster."
