# Idempotent: reusa o container se ja existir. Requer Docker (rode o
# instalador do Docker deste mesmo step antes).
command -v docker &>/dev/null || fail "docker nao instalado — rode o instalador do Docker neste mesmo step antes"

if docker ps -a --format '{{.Names}}' | grep -qx traefik; then
  echo "==> traefik ja existe, garantindo que esta rodando"
  docker start traefik &>/dev/null || true
else
  echo "==> subindo container traefik (80/443 publicas, dashboard so em localhost)"
  # --api.insecure=true (dashboard sem auth propria) so e aceitavel porque a
  # porta 8080 esta amarrada em 127.0.0.1 — mesma postura do proprio painel
  # server-safe, acesso via tunel SSH, nunca exposto direto.
  docker run -d \
    --name traefik \
    --restart=always \
    -p 80:80 -p 443:443 \
    -p 127.0.0.1:8080:8080 \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    traefik:v3.1 \
    --api.dashboard=true \
    --api.insecure=true \
    --providers.docker=true \
    --providers.docker.exposedbydefault=false \
    --entrypoints.web.address=:80 \
    --entrypoints.websecure.address=:443
fi

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx traefik || fail "container traefik nao esta rodando"

echo "==> ok"
result "ok" "traefik rodando (dashboard via tunel SSH)" "{\"dashboard\":\"http://127.0.0.1:8080\"}"
