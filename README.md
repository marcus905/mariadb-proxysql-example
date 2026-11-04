# MariaDB Galera + ProxySQL lab

A three-node **MariaDB Galera** cluster behind **ProxySQL**. A SQL client on another machine connects to the **Docker host's IP address on TCP port 6033**; the Galera database ports are private to the Docker network. The ProxySQL admin port (6032) is bound to localhost.

> **Disposable training environment, not a production deployment.** Passwords are examples. The lab assumes a single Docker host, is not a highly available proxy tier, and has no TLS/firewall automation.

## Components

- MariaDB 11.4: `galera1`, `galera2`, `galera3`; synchronous Galera replication.
- ProxySQL 3.0.1: client listener on `0.0.0.0:6033`, admin listener published on `127.0.0.1:6032`.
- ProxySQL Galera hostgroups: writer **10**, backup writers **20**, readers **30**, offline **40**. The initial user routes to writer hostgroup 10.
- Database `labdb`, user `labuser` / `labpass`. Monitoring user `monitor` / `monitorpass`.

The **6033** mapping and a listener bound to `0.0.0.0` are essential: exposing only ProxySQL's admin port 6032 does **not** expose its SQL frontend. Remote clients must also be permitted by the host firewall and any VM/cloud security rules.

## Requirements

Docker Engine and Docker Compose v2 on Linux, macOS, or Windows (Docker Desktop). The first startup needs free TCP ports 6033 and 6032 on the host.

## First startup — new, empty volumes only

```bash
git clone https://github.com/marcus905/mariadb-proxysql-example.git
cd mariadb-proxysql-example
cp .env.example .env
bash scripts/up.sh
bash scripts/check.sh
```

The startup script bootstraps `galera1` as the initial primary component, joins the other two nodes, then recreates `galera1` **without** the bootstrap option before starting ProxySQL. It **refuses to bootstrap if existing Galera volumes are found**, to avoid unsafe split-brain recovery.

After startup, subsequent container restarts should use `docker compose up -d` only while the existing Galera primary component is healthy. After a full-cluster outage, follow MariaDB's documented Galera recovery procedure (check `grastate.dat`, `safe_to_bootstrap`, and recovered seqno); this lab deliberately does not automate unsafe recovery.

## Connect from the Docker host

```bash
mariadb --protocol=tcp -h127.0.0.1 -P6033 -ulabuser -plabpass labdb
```

For a **different computer**, substitute `<DOCKER_HOST_LAN_IP>` for `127.0.0.1`:

```bash
mariadb --protocol=tcp -h<DOCKER_HOST_LAN_IP> -P6033 -ulabuser -plabpass labdb
```

In DBeaver, MySQL Workbench, or another compatible client: host = Docker host's reachable LAN address, port = **6033**, user = `labuser`, password = `labpass`, database = `labdb`. Use MySQL/MariaDB TCP protocol. Do **not** use a container hostname on an external computer: Docker service names resolve only within the Docker network.

The port is exposed on all host interfaces. **Allow TCP 6033 only from your trusted lab network**; do not expose this demo directly to the public Internet. For Internet access, use VPN or SSH tunneling and secure credentials/TLS instead.

## Verify queries and cluster state

```sql
SELECT @@hostname AS serving_node;
CREATE TABLE IF NOT EXISTS labdb.probe (id INT PRIMARY KEY, message VARCHAR(100)) ENGINE=InnoDB;
INSERT INTO labdb.probe VALUES (1, 'via proxysql') ON DUPLICATE KEY UPDATE message=VALUES(message);
SELECT * FROM labdb.probe;
```

To inspect the three nodes and the Galera status:

```bash
bash scripts/check.sh
docker compose exec galera2 mariadb -uroot -p -e "SELECT * FROM labdb.probe;"
```

Inspect ProxySQL from the Docker host (admin restricted to localhost):

```bash
mariadb --protocol=tcp -h127.0.0.1 -P6032 -uradmin -pradminpass -e "SELECT hostgroup_id,hostname,port,status FROM runtime_mysql_servers;"
```

ProxySQL tracks a Galera writer; a simple `SELECT` does **not** necessarily round-robin across all nodes because this lab intentionally defaults to the writer and does not set query-based read/write splitting. ProxySQL's SQLite-backed configuration is persisted in its volume: changing `proxysql.cnf` later may require applying changes in the admin interface or resetting the **disposable** ProxySQL volume.

## Troubleshooting remote access

1. Check `docker compose ps`: ProxySQL should show `0.0.0.0:6033->6033/tcp`.
2. On the Docker host, test `mariadb -h127.0.0.1 -P6033 -ulabuser -plabpass --protocol=tcp`. If this fails, inspect `docker compose logs proxysql galera1`.
3. From the external machine, check reachability (e.g. `nc -vz <DOCKER_HOST_LAN_IP> 6033`). A timeout/refusal usually indicates network/firewall/port publishing; authentication errors point to user configuration.
4. Check Galera health: `wsrep_cluster_size=3`, `wsrep_cluster_status=Primary`, `wsrep_ready=ON`, `wsrep_local_state_comment=Synced`.
5. In ProxySQL's admin interface, inspect `runtime_mysql_servers`, `stats_mysql_connection_pool`, and `monitor.mysql_server_galera_log` (monitor logs are stored in ProxySQL's monitor schema).

## Stop / reset

```bash
docker compose down
```

For a **destructive reset of this disposable lab** (deletes all database and ProxySQL data):

```bash
docker compose down -v
bash scripts/up.sh
```

Do **not** delete volumes to recover valuable data.

## References

- [SesameDisk — MariaDB Galera + ProxySQL](https://sesamedisk.com/mysql-cluster-deploy-galera-with-mariadb-proxysql/)
- [ivangfr — springboot-proxysql-mysql](https://github.com/ivangfr/springboot-proxysql-mysql) (MySQL primary/replica, **not** Galera)
- [MariaDB Galera bootstrap documentation](https://mariadb.com/docs/galera-cluster/high-availability/initializing-a-new-cluster)
- [ProxySQL documentation](https://proxysql.com/documentation/)
