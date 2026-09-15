# Aborta se docker ja estiver instalado (nao reinstala/reconfigura em cima).
# ensure_docker() (common.sh) concentra a logica de instalar/habilitar/
# validar, reaproveitada por Portainer/Traefik/etc quando precisam do Docker
# como dependencia — la, presenca previa e sucesso silencioso (dependencia
# resolvida), so aqui (o proprio botao "instalar docker") vira erro.
command -v docker &>/dev/null && fail "docker ja esta instalado"

ensure_docker

DOCKER_VERSION=$(json_escape "$(docker --version 2>/dev/null)")

echo "==> ok"
result "ok" "docker instalado e ativo" "{\"version\":\"$DOCKER_VERSION\"}"
