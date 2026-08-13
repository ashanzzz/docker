# Build staging only

Do not maintain business source code here.

GitHub Actions and `scripts/build-local.sh` populate:

```text
custom-apps/ashan_cn_procurement
```

from:

```text
https://github.com/ashanzzz/erpnext-private-customizations
```

The directory is build input only. The Ashan repository remains the source of
truth.
