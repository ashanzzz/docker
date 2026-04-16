#!/usr/bin/env bash
set -euo pipefail

: "${BENCH_WORKER_QUEUES:=long,default,short}"
exec bench worker --queue "${BENCH_WORKER_QUEUES}"
