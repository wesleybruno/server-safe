# Aborta se ja estiver instalado (nao reinstala/reconfigura em cima). Requer
# Docker — instala junto (ensure_docker, common.sh) se ainda nao tiver.
#
# Mesma rede "server-safe-monitoring" do cAdvisor/Grafana/Loki (se
# instalados) — nenhum scrape/datasource e configurado automaticamente de
# proposito, mas o admin pode adicionar um job pra "cadvisor:8080" no
# config depois, ja que os containers se enxergam pelo nome nessa rede.
command -v docker &>/dev/null || ensure_docker

docker ps -a --format '{{.Names}}' | grep -qx prometheus && fail "prometheus ja esta instalado"

docker network create server-safe-monitoring &>/dev/null || true

mkdir -p /etc/prometheus
cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
EOF

echo "==> subindo container prometheus (metricas, so em localhost)"
docker run -d \
  --name prometheus \
  --restart=always \
  --network server-safe-monitoring \
  -p 127.0.0.1:9090:9090 \
  -v /etc/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  -v prometheus-data:/prometheus \
  prom/prometheus:latest

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx prometheus || fail "container prometheus nao esta rodando"

echo "==> ok"
result "ok" "prometheus rodando (acesse via tunel SSH)" "{\"url\":\"http://127.0.0.1:9090\"}"
