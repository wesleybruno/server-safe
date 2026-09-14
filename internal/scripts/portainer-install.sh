# Idempotent: reusa o container se ja existir. Requer Docker (rode o
# instalador do Docker deste mesmo step antes).
command -v docker &>/dev/null || fail "docker nao instalado — rode o instalador do Docker neste mesmo step antes"

if docker ps -a --format '{{.Names}}' | grep -qx portainer; then
  echo "==> portainer ja existe, garantindo que esta rodando"
  docker start portainer &>/dev/null || true
else
  echo "==> criando volume e subindo container portainer"
  docker volume create portainer_data >/dev/null
  # 9443 (HTTPS mgmt UI) so em localhost, de proposito: mesma postura do
  # proprio painel server-safe — acesso via tunel SSH, nunca exposto direto.
  docker run -d \
    --name portainer \
    --restart=always \
    -p 127.0.0.1:9443:9443 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:lts
fi

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx portainer || fail "container portainer nao esta rodando"

echo "==> ok"
result "ok" "portainer rodando (acesse via tunel SSH)" "{\"url\":\"https://127.0.0.1:9443\"}"
