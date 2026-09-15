# Instalador oficial (cdn.coollabs.io) roda como root via este painel
# local-only — mesmo trust boundary do admin rodando na mao. Ele instala o
# Docker sozinho se faltar, nao depende do step Docker deste wizard.
ensure_installed curl curl

[[ -d /data/coolify ]] && fail "coolify ja esta instalado"

echo "==> rodando instalador oficial do coolify (instala docker sozinho se faltar)"
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

echo "==> validando"
sleep 3
docker ps --format '{{.Names}}' 2>/dev/null | grep -qi coolify || fail "container coolify nao encontrado apos instalacao"

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "==> ok"
result "ok" "coolify instalado" "{\"url\":\"http://${IP:-SEU_IP}:8000\"}"
