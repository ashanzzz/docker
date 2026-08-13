# Technical route

## Build plane

1. GitHub Action resolves official ERPNext v16.
2. GitHub Action fetches `ashanzzz/erpnext-private-customizations@main`.
3. Ashan source commit is recorded.
4. `frappe/build:version-16` runs `bench init` for Frappe + ERPNext.
5. Ashan is copied into `apps/` and installed into the Bench Python env.
6. `sites/apps.txt` is written exactly once with three app names.
7. Ashan direct `public/` files are linked into `sites/assets/`.
8. Final runtime image is based on `frappe/base:version-16`.
9. Only nginx + supervisor are added.
10. Image is pushed and smoke-tested.

## Runtime plane

Required persistent state:

```text
/home/frappe/frappe-bench/sites
```

Required external services:

```text
MariaDB
Redis cache
Redis queue
Redis socketio
```

Processes inside the container:

```text
nginx
gunicorn
socketio
worker
scheduler
```

## Upgrade plane

ERPNext version update:
- GitHub Actions builds a new image.
- Startup runs migrate before services.

Ashan update:
- push Ashan main
- optionally dispatch Docker build automatically
- new image contains that exact Ashan commit
- startup migrates the existing site

## State ownership

Container image:
- code
- Python environment
- generated application assets
- supervisor/nginx configuration

Sites volume:
- site configuration
- public/private files
- generated site assets
- site metadata

External MariaDB:
- all business data

External Redis:
- cache / queue / socketio state

No application source code is writable/persistent outside the image.
