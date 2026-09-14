# Idempotent: reusa o container se ja existir. Requer Docker — instala
# junto (ensure_docker, common.sh) se ainda nao tiver, sem show de erro
# separado. So le o socket do Docker (:ro), nao precisa de mais nada.
command -v docker &>/dev/null || ensure_docker

if docker ps -a --format '{{.Names}}' | grep -qx dozzle; then
  echo "==> dozzle ja existe, garantindo que esta rodando"
  docker start dozzle &>/dev/null || true
else
  echo "==> subindo container dozzle (logs dos containers Docker, so em localhost)"
  docker run -d \
    --name dozzle \
    --restart=always \
    -p 127.0.0.1:8081:8080 \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    amir20/dozzle:latest
fi

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx dozzle || fail "container dozzle nao esta rodando"

echo "==> ok"
result "ok" "dozzle rodando (acesse via tunel SSH)" "{\"url\":\"http://127.0.0.1:8081\"}"
