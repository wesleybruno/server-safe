# Instalador oficial (get.easypanel.io) roda como root via este painel
# local-only — mesmo trust boundary do admin rodando na mao. Ele instala o
# Docker sozinho se faltar, nao depende do step Docker deste wizard.
ensure_installed curl curl

docker service ls 2>/dev/null | grep -qi easypanel && fail "easypanel ja esta instalado"

echo "==> rodando instalador oficial do easypanel (instala docker sozinho se faltar)"
curl -sSL https://get.easypanel.io | sh

echo "==> validando"
sleep 3
docker service ls 2>/dev/null | grep -qi easypanel || fail "servico easypanel nao encontrado apos instalacao"

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "==> ok"
result "ok" "easypanel instalado" "{\"url\":\"https://${IP:-SEU_IP}:3000\"}"
