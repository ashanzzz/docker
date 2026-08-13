# Single-container ERPNext16 application AIO

The container runs only application processes:

- nginx
- gunicorn backend
- websocket
- background worker
- scheduler

MariaDB and Redis are external and mandatory.

Startup is deterministic:

1. validate environment;
2. normalize `sites/apps.txt` to `frappe`, `erpnext`, `ashan_cn_procurement`;
3. write external DB/Redis configuration;
4. refresh image-generated assets when the image changes;
5. verify DB/Redis endpoints;
6. create the site if absent;
7. install missing ERPNext/Ashan apps;
8. run `bench migrate`;
9. validate nginx configuration;
10. start Supervisor.

No application process starts before migration succeeds.
