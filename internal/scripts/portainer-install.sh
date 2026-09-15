# Aborta se ja estiver instalado (nao reinstala/reconfigura em cima). Requer
# Docker — instala junto (ensure_docker, common.sh) se ainda nao tiver, sem
# show de erro separado.
command -v docker &>/dev/null || ensure_docker

docker ps -a --format '{{.Names}}' | grep -qx portainer && fail "portainer ja esta instalado"

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

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx portainer || fail "container portainer nao esta rodando"

echo "==> ok"
result "ok" "portainer rodando (acesse via tunel SSH)" "{\"url\":\"https://127.0.0.1:9443\"}"
