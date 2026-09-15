# Idempotent: reusa o container se ja existir. Requer Docker — instala
# junto (ensure_docker, common.sh) se ainda nao tiver. Usa a config padrao
# que ja vem na imagem (nao escreve config proprio) — o quickstart oficial
# do Loki funciona sem mount nenhum, so precisa persistir os dados.
command -v docker &>/dev/null || ensure_docker

docker network create server-safe-monitoring &>/dev/null || true

if docker ps -a --format '{{.Names}}' | grep -qx loki; then
  echo "==> loki ja existe, garantindo que esta rodando"
  docker start loki &>/dev/null || true
else
  echo "==> subindo container loki (armazenamento de logs, so em localhost)"
  docker run -d \
    --name loki \
    --restart=always \
    --network server-safe-monitoring \
    -p 127.0.0.1:3100:3100 \
    -v loki-data:/loki \
    grafana/loki:latest
fi

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx loki || fail "container loki nao esta rodando"

echo "==> ok"
result "ok" "loki rodando — adicione http://loki:3100 como datasource no Grafana (mesma rede docker)" "{\"url\":\"http://127.0.0.1:3100\"}"
