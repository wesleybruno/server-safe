# Aborta se ja estiver instalado (nao reinstala/reconfigura em cima). Requer
# Docker — instala junto (ensure_docker, common.sh) se ainda nao tiver, sem
# show de erro separado.
#
# Fica na rede "server-safe-monitoring" junto com Prometheus/Grafana/Loki/
# cAdvisor (se instalados) — nao faz wiring automatico de datasource/scrape
# target (cada extra e independente de proposito), mas assim da pra
# referenciar pelo nome do container ("node-exporter:9100") na hora de
# configurar manualmente um scrape job do Prometheus.
#
# --pid host + bind /:/host:ro,rslave e o padrao oficial do node_exporter
# pra metricas de host completas (nao --network=host, mesma razao do
# netdata: a porta fica mapeada e restrita a 127.0.0.1, --network=host
# quebraria isso).
command -v docker &>/dev/null || ensure_docker

docker network create server-safe-monitoring &>/dev/null || true

docker ps -a --format '{{.Names}}' | grep -qx node-exporter && fail "node-exporter ja esta instalado"

echo "==> subindo container node-exporter (metricas de host, so em localhost)"
docker run -d \
  --name node-exporter \
  --restart=always \
  --network server-safe-monitoring \
  --pid host \
  -p 127.0.0.1:9100:9100 \
  -v /:/host:ro,rslave \
  prom/node-exporter:latest \
  --path.rootfs=/host

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx node-exporter || fail "container node-exporter nao esta rodando"

echo "==> ok"
result "ok" "node-exporter rodando (acesse via tunel SSH)" "{\"url\":\"http://127.0.0.1:9100\"}"
