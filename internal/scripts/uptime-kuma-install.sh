# Aborta se ja estiver instalado (nao reinstala/reconfigura em cima). Requer
# Docker — instala junto (ensure_docker, common.sh) se ainda nao tiver, sem
# show de erro separado.
command -v docker &>/dev/null || ensure_docker

docker ps -a --format '{{.Names}}' | grep -qx uptime-kuma && fail "uptime-kuma ja esta instalado"

echo "==> subindo container uptime-kuma (monitor de uptime, so em localhost)"
docker run -d \
  --name uptime-kuma \
  --restart=always \
  -p 127.0.0.1:8082:3001 \
  -v uptime-kuma:/app/data \
  louislam/uptime-kuma:1

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx uptime-kuma || fail "container uptime-kuma nao esta rodando"

echo "==> ok"
result "ok" "uptime-kuma rodando (acesse via tunel SSH)" "{\"url\":\"http://127.0.0.1:8082\"}"
