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

The startup script bootstraps `galera1` as the initial primary component, joins the other two nodes, then recreates `galera1` **without** the bootstrap option before starting ProxySQL and configures its Galera hostgroups via the ProxySQL Admin interface. It **refuses to bootstrap if existing Galera volumes are found**, to avoid unsafe split-brain recovery.

After startup, subsequent container restarts should use `docker compose up -d` only while the existing Galera primary component is healthy. After a full-cluster outage, follow MariaDB's documented Galera recovery procedure (check `grastate.dat`, `safe_to_bootstrap`, and recovered seqno); this lab deliberately does not automate unsafe recovery.

## Windows: Docker Desktop + PowerShell

Run these commands in **PowerShell 5.1 or PowerShell 7** with Docker Desktop running in Linux-container mode. No Git Bash or host-side MariaDB client is required for the first deployment or health checks.

```powershell
git clone https://github.com/marcus905/mariadb-proxysql-example.git
Set-Location mariadb-proxysql-example
Copy-Item .env.example .env
.\scripts\up.ps1
.\scripts\check.ps1
```

If Windows blocks unsigned local scripts, use a **process-only** policy for this terminal (do not change machine-wide policy):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

The PowerShell files mirror the Bash workflow:

- `scripts/up.ps1`: first deployment **only**, and refuses to bootstrap existing Galera data volumes.
- `scripts/configure-proxysql.ps1`: applies and persists ProxySQL Galera hostgroups.
- `scripts/check.ps1`: checks each Galera node, inspects ProxySQL backend status, and tests SQL connectivity through port 6033.
- `scripts/test-connection.ps1`: test the host-published TCP port and log in via ProxySQL using the local MariaDB CLI, or a **temporary MariaDB Docker client** if no CLI is installed.
- `scripts/common.ps1`: shared helpers; not intended to be run directly.

To check the port from **another Windows computer** on the LAN, without requiring Docker or a SQL client:

```powershell
.\scripts\test-connection.ps1 -HostName 192.168.1.50 -Port 6033 -TcpOnly
```

Replace `192.168.1.50` with the Docker host's LAN IP. `-TcpOnly` proves the TCP listener is reachable, **not** that SQL authentication or routing works. For a full SQL login from the remote Windows computer, install the MariaDB CLI or Docker Desktop and omit `-TcpOnly`:

```powershell
.\scripts\test-connection.ps1 -HostName 192.168.1.50 -Port 6033
```

Default demo credentials for the SQL test are `labuser` / `labpass` on `labdb`; override with `-Username`, `-Password`, `-Database` as needed. `-Port` defaults to `PROXYSQL_PORT` from the local `.env` file or 6033. The temporary Docker client uses `host.docker.internal` when connecting to the local Windows Docker host. If Docker Desktop has a custom networking setup, use a host-installed MariaDB client instead.

To stop the containers without deleting database data:

```powershell
docker compose down
```

**Destructive lab reset, only if no data must be retained:**

```powershell
docker compose down -v
.\scripts\up.ps1
```

Do not use `up.ps1` to recover a cluster after a full outage. Follow the Galera recovery procedure rather than automatically bootstrapping an arbitrary node.

### Windows line endings (Git for Windows)

The repository's `.gitattributes` forces Unix LF line endings for `.sh` files mounted into Linux containers, regardless of `core.autocrlf`. On an existing Windows checkout created **before** this rule, refresh the working-tree copies in PowerShell:

```powershell
git pull --ff-only
git ls-files -- '*.sh' | ForEach-Object { git checkout-index --force -- $_ }
```

`checkout-index --force` replaces the listed working-tree shell files with the committed versions; **do not run it if you have uncommitted edits to shell scripts**. No Docker volume reset is required for this line-ending problem. Restart the initial deployment only if it never initialized successfully:

```powershell
.\scripts\up.ps1
```

If the first failed start created a Galera data volume, the bootstrap script will refuse to reuse it. For a **brand-new disposable lab with no data to preserve**, run `docker compose down -v` before `up.ps1`; never delete volumes containing valuable data.

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

### Galera shows 3 members but `non-Primary`

A cluster can report `wsrep_cluster_size=3` but still be **unavailable** if
`wsrep_cluster_status=non-Primary` and `wsrep_ready=OFF`. Membership alone
does not prove that a Primary Component has been established. Check:

```powershell
docker compose ps -a
docker compose logs --tail=150 galera1 galera2 galera3
```

If logs report `No node with complete state` or `Failed to establish quorum`,
one likely cause during first deployment is that the bootstrap node was restarted
before joining peers reached the `Synced` state. The current `up.ps1` and
`up.sh` explicitly wait for all three peers to become `Synced` before
recreating the bootstrap node, and wait for it to rejoin before starting ProxySQL.

**Only for a brand-new disposable environment with NO data to preserve:**

```powershell
git pull --ff-only
docker compose down -v
.\scripts\up.ps1
.\scripts\check.ps1
```

`down -v` permanently removes the MariaDB and ProxySQL volumes. **Never**
use this reset for data you need to keep. For non-disposable data, follow
[MariaDB's quorum-reset and recovery guidance](https://mariadb.com/docs/galera-cluster/high-availability/resetting-the-quorum-cluster-bootstrap):
verify there is no other Primary Component, compare the last committed
transaction positions on all available nodes, and recover a **single**
Primary Component from the most advanced node. Do not issue `pc.bootstrap`
indiscriminately on an arbitrary node or on multiple partitions.

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
