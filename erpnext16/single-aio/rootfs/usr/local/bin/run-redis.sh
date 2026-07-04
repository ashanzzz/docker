#!/usr/bin/env bash
set -euo pipefail

exec /usr/bin/redis-server --appendonly yes --dir /var/lib/redis
