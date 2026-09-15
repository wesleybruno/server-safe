# Idempotent: reusa cada container se ja existir, reaproveita a senha do
# banco se ja gerada. Requer Docker — instala junto (ensure_docker,
# common.sh) se ainda nao tiver.
#
# O extra mais pesado do grupo: 3 containers (Postgres + zabbix-server +
# zabbix-web), nao 1 — sem o orquestrador com healthcheck que o
# docker-compose oficial do Zabbix usa, entao o web pode reclamar de banco
# por um minuto ou dois no primeiro boot ate o server terminar de criar o
# schema. --restart=always cobre isso, sobe sozinho quando o banco fica
# pronto.
command -v docker &>/dev/null || ensure_docker

docker network create server-safe-zabbix &>/dev/null || true

mkdir -p /etc/zabbix
chmod 700 /etc/zabbix

if [[ -s /etc/zabbix/db-password ]]; then
  echo "==> senha do banco ja existe, reaproveitando"
  DB_PASSWORD=$(cat /etc/zabbix/db-password)
else
  DB_PASSWORD=$(random_password)
  printf '%s' "$DB_PASSWORD" > /etc/zabbix/db-password
  chmod 600 /etc/zabbix/db-password
  echo "==> senha do banco gerada"
fi

if docker ps -a --format '{{.Names}}' | grep -qx zabbix-postgres; then
  echo "==> zabbix-postgres ja existe, garantindo que esta rodando"
  docker start zabbix-postgres &>/dev/null || true
else
  echo "==> subindo container zabbix-postgres"
  docker run -d \
    --name zabbix-postgres \
    --restart=always \
    --network server-safe-zabbix \
    -e POSTGRES_USER=zabbix \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -e POSTGRES_DB=zabbix \
    -v zabbix-postgres:/var/lib/postgresql/data \
    postgres:16-alpine
fi

if docker ps -a --format '{{.Names}}' | grep -qx zabbix-server; then
  echo "==> zabbix-server ja existe, garantindo que esta rodando"
  docker start zabbix-server &>/dev/null || true
else
  echo "==> subindo container zabbix-server"
  docker run -d \
    --name zabbix-server \
    --restart=always \
    --network server-safe-zabbix \
    -e DB_SERVER_HOST=zabbix-postgres \
    -e POSTGRES_USER=zabbix \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -e POSTGRES_DB=zabbix \
    -v zabbix-server:/var/lib/zabbix \
    zabbix/zabbix-server-pgsql:latest
fi

if docker ps -a --format '{{.Names}}' | grep -qx zabbix-web; then
  echo "==> zabbix-web ja existe, garantindo que esta rodando"
  docker start zabbix-web &>/dev/null || true
else
  echo "==> subindo container zabbix-web (so em localhost)"
  docker run -d \
    --name zabbix-web \
    --restart=always \
    --network server-safe-zabbix \
    -p 127.0.0.1:8084:8080 \
    -e ZBX_SERVER_HOST=zabbix-server \
    -e DB_SERVER_HOST=zabbix-postgres \
    -e POSTGRES_USER=zabbix \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -e POSTGRES_DB=zabbix \
    zabbix/zabbix-web-nginx-pgsql:latest
fi

echo "==> validando"
sleep 3
for c in zabbix-postgres zabbix-server zabbix-web; do
  docker ps --format '{{.Names}}' | grep -qx "$c" || fail "container $c nao esta rodando"
done

echo "==> ok"
result "ok" "zabbix rodando — login inicial Admin/zabbix, troque assim que entrar (acesse via tunel SSH; primeiro boot pode levar 1-2min pro banco terminar de inicializar)" "{\"url\":\"http://127.0.0.1:8084\"}"
