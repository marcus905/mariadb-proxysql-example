#!/usr/bin/env bash
set -e
if [ "${GALERA_BOOTSTRAP:-0}" = "1" ]; then
  echo "Bootstrapping first Galera node (initial deployment only)"
  exec /usr/local/bin/docker-entrypoint.sh "$@" --wsrep-new-cluster
fi
exec /usr/local/bin/docker-entrypoint.sh "$@"
