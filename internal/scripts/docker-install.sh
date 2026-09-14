# Idempotent: toda a logica de instalar/habilitar/validar vive em
# ensure_docker() (common.sh), reaproveitada por Portainer/Traefik quando
# precisam do Docker como dependencia.
ensure_docker

DOCKER_VERSION=$(json_escape "$(docker --version 2>/dev/null)")

echo "==> ok"
result "ok" "docker instalado e ativo" "{\"version\":\"$DOCKER_VERSION\"}"
