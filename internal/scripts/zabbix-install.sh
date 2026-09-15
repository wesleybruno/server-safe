# Aborta se ja estiver instalado (nao reinstala/reconfigura em cima) — checa
# so o primeiro container (zabbix-postgres), os outros dois sempre sobem
# junto no mesmo run. Requer Docker — instala junto (ensure_docker,
# common.sh) se ainda nao tiver.
#
# O extra mais pesado do grupo: 3 containers (Postgres + zabbix-server +
# zabbix-web), nao 1 — sem o orquestrador com healthcheck que o
# docker-compose oficial do Zabbix usa, entao o web pode reclamar de banco
# por um minuto ou dois no primeiro boot ate o server terminar de criar o
# schema. --restart=always cobre isso, sobe sozinho quando o banco fica
# pronto.
command -v docker &>/dev/null || ensure_docker

docker ps -a --format '{{.Names}}' | grep -qx zabbix-postgres && fail "zabbix ja esta instalado"

docker network create server-safe-zabbix &>/dev/null || true

mkdir -p /etc/zabbix
chmod 700 /etc/zabbix
DB_PASSWORD=$(random_password)
printf '%s' "$DB_PASSWORD" > /etc/zabbix/db-password
chmod 600 /etc/zabbix/db-password

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

echo "==> validando"
sleep 3
for c in zabbix-postgres zabbix-server zabbix-web; do
  docker ps --format '{{.Names}}' | grep -qx "$c" || fail "container $c nao esta rodando"
done

echo "==> ok"
result "ok" "zabbix rodando — login inicial Admin/zabbix, troque assim que entrar (acesse via tunel SSH; primeiro boot pode levar 1-2min pro banco terminar de inicializar)" "{\"url\":\"http://127.0.0.1:8084\"}"
