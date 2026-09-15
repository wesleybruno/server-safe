# Aborta se ja estiver instalado (nao reinstala/reconfigura em cima). Requer
# Docker — instala junto (ensure_docker, common.sh) se ainda nao tiver. Usa a
# config padrao que ja vem na imagem (nao escreve config proprio) — o
# quickstart oficial do Loki funciona sem mount nenhum, so precisa persistir
# os dados.
command -v docker &>/dev/null || ensure_docker

docker ps -a --format '{{.Names}}' | grep -qx loki && fail "loki ja esta instalado"

docker network create server-safe-monitoring &>/dev/null || true

echo "==> subindo container loki (armazenamento de logs, so em localhost)"
docker run -d \
  --name loki \
  --restart=always \
  --network server-safe-monitoring \
  -p 127.0.0.1:3100:3100 \
  -v loki-data:/loki \
  grafana/loki:latest

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx loki || fail "container loki nao esta rodando"

echo "==> ok"
result "ok" "loki rodando — adicione http://loki:3100 como datasource no Grafana (mesma rede docker)" "{\"url\":\"http://127.0.0.1:3100\"}"
