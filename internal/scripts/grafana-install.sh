# Idempotent: reusa o container se ja existir. Requer Docker — instala
# junto (ensure_docker, common.sh) se ainda nao tiver.
#
# Mesma rede "server-safe-monitoring" do Prometheus/Loki/cAdvisor (se
# instalados) — os datasources nao sao pre-configurados de proposito (cada
# extra e independente), mas o admin pode adicionar "http://prometheus:9090"
# e "http://loki:3100" como datasource dentro do Grafana sem precisar
# descobrir IP, ja que estao na mesma rede docker.
command -v docker &>/dev/null || ensure_docker

docker network create server-safe-monitoring &>/dev/null || true

if docker ps -a --format '{{.Names}}' | grep -qx grafana; then
  echo "==> grafana ja existe, garantindo que esta rodando"
  docker start grafana &>/dev/null || true
else
  echo "==> subindo container grafana (dashboards, so em localhost)"
  docker run -d \
    --name grafana \
    --restart=always \
    --network server-safe-monitoring \
    -p 127.0.0.1:3000:3000 \
    -v grafana-data:/var/lib/grafana \
    grafana/grafana:latest
fi

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx grafana || fail "container grafana nao esta rodando"

echo "==> ok"
result "ok" "grafana rodando — login inicial admin/admin, troca no primeiro acesso (acesse via tunel SSH)" "{\"url\":\"http://127.0.0.1:3000\"}"
