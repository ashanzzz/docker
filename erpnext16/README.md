# ERPNext16 — external-only AIO

This directory has one supported deployment architecture.

```text
ERPNext16 container
  nginx
  gunicorn
  websocket
  worker
  scheduler

External services
  MariaDB
  Redis cache
  Redis queue
  Redis socketio
```

There is no bundled MariaDB or Redis mode.

## Custom app

`ashan_cn_procurement` remains in:

```text
ashanzzz/erpnext-private-customizations
```

CI fetches its `main` branch into `custom-apps/ashan_cn_procurement` only for
the Docker build. The resulting image contains Frappe, ERPNext and Ashan.

## Build

GitHub Actions:

```text
.github/workflows/erpnext16-single-container-aio.yml
```

Local build:

```bash
./scripts/build-local.sh
```

Both use:

```text
single-aio/Containerfile
apps.json
```

## Runtime persistence

Persist only:

```text
/home/frappe/frappe-bench/sites
```

Business data is stored in external MariaDB. Queue/cache/socketio state is in
external Redis.

## Required environment

```text
SITE_NAME
FRAPPE_DB_TYPE=mariadb
FRAPPE_DB_HOST
FRAPPE_DB_PORT=3306
FRAPPE_DB_NAME
FRAPPE_DB_USER
FRAPPE_DB_PASSWORD
FRAPPE_REDIS_CACHE
FRAPPE_REDIS_QUEUE
FRAPPE_REDIS_SOCKETIO
```

`ADMIN_PASSWORD` is only needed when the site does not yet exist.
