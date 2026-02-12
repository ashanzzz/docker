#!/bin/bash
# 运行 ERPNext 16 AIO 容器
# 支持两种模式：使用内部 MariaDB（默认）或使用外部数据库

# 基础配置（可根据需要覆盖）
: ${IMAGE:=ghcr.io/ashanzzz/erpnext16-aio:latest}
: ${NAME:=erpnext16-aio}
: ${HTTP_PORT:=80}
: ${MARIADB_ROOT_PASSWORD:=Pass1234}
: ${ADMIN_PASSWORD:=admin}
: ${SITE_NAME:=site1.local}

# 使用内部数据库（默认）
if [[ -z "$EXTERNAL_DB" ]]; then
    echo "启动 ERPNext 16 AIO（使用内部 MariaDB）..."
    docker run -d \
        --name $NAME \
        -p $HTTP_PORT:80 \
        -e MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD \
        -e ADMIN_PASSWORD=$ADMIN_PASSWORD \
        -e SITE_NAME=$SITE_NAME \
        -v erpnext16-sites:/home/frappe/frappe-bench/sites \
        -v erpnext16-mysql:/var/lib/mysql \
        $IMAGE
    echo "容器已启动。访问 http://localhost:$HTTP_PORT 并使用管理员密码 $ADMIN_PASSWORD 登录。"
    exit 0
fi

# 使用外部数据库（示例：通过 Docker Compose 或外部主机）
# 请确保外部数据库已准备好，并设置以下环境变量：
# DB_HOST, DB_PORT, DB_ROOT_USER, DB_ROOT_PASSWORD
echo "启动 ERPNext 16 AIO（使用外部数据库）..."
docker run -d \
    --name $NAME \
    -p $HTTP_PORT:80 \
    -e DB_HOST=$DB_HOST \
    -e DB_PORT=$DB_PORT \
    -e DB_ROOT_USER=$DB_ROOT_USER \
    -e DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD \
    -e ADMIN_PASSWORD=$ADMIN_PASSWORD \
    -e SITE_NAME=$SITE_NAME \
    -v erpnext16-sites:/home/frappe/frappe-bench/sites \
    $IMAGE
echo "容器已启动。访问 http://localhost:$HTTP_PORT 并使用管理员密码 $ADMIN_PASSWORD 登录。"