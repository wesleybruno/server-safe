# Aborta se ja estiver instalado (nao reinstala/reconfigura em cima). Requer
# Docker — instala junto (ensure_docker, common.sh) se ainda nao tiver, sem
# show de erro separado.
#
# Fica na rede "server-safe-monitoring" junto com Prometheus/Grafana/Loki
# (se instalados) — nao faz wiring automatico de datasource/scrape target
# (cada extra e independente de proposito), mas assim da pra referenciar
# pelo nome do container ("cadvisor:8080") na hora de configurar manualmente
# um scrape job do Prometheus, sem precisar descobrir IP.
command -v docker &>/dev/null || ensure_docker

docker network create server-safe-monitoring &>/dev/null || true

docker ps -a --format '{{.Names}}' | grep -qx cadvisor && fail "cadvisor ja esta instalado"

echo "==> subindo container cadvisor (metricas de containers, so em localhost)"
docker run -d \
  --name cadvisor \
  --restart=always \
  --network server-safe-monitoring \
  -p 127.0.0.1:8083:8080 \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:rw \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:latest

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx cadvisor || fail "container cadvisor nao esta rodando"

echo "==> ok"
result "ok" "cadvisor rodando (acesse via tunel SSH)" "{\"url\":\"http://127.0.0.1:8083\"}"
