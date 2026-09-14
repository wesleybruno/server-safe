# Idempotent: reusa o container se ja existir. Requer Docker — instala
# junto (ensure_docker, common.sh) se ainda nao tiver, sem show de erro
# separado.
#
# Bridge + porta mapeada (nao --network=host, que a doc oficial do netdata
# recomenda pra metricas completas de rede do host): --network=host
# escutaria em todas as interfaces direto, sem como restringir a
# 127.0.0.1 — quebraria a postura deste projeto inteiro de UI de admin so
# em loopback. Perde um pouco de granularidade de metricas de rede, troca
# aceitavel.
command -v docker &>/dev/null || ensure_docker

if docker ps -a --format '{{.Names}}' | grep -qx netdata; then
  echo "==> netdata ja existe, garantindo que esta rodando"
  docker start netdata &>/dev/null || true
else
  echo "==> subindo container netdata (monitoramento, so em localhost)"
  docker run -d \
    --name netdata \
    --restart=always \
    -p 127.0.0.1:19999:19999 \
    -v netdataconfig:/etc/netdata \
    -v netdatalib:/var/lib/netdata \
    -v netdatacache:/var/cache/netdata \
    -v /etc/passwd:/host/etc/passwd:ro \
    -v /etc/group:/host/etc/group:ro \
    -v /proc:/host/proc:ro \
    -v /sys:/host/sys:ro \
    -v /etc/os-release:/host/etc/os-release:ro \
    --cap-add SYS_PTRACE \
    --cap-add SYS_ADMIN \
    --security-opt apparmor=unconfined \
    netdata/netdata
fi

echo "==> validando"
sleep 2
docker ps --format '{{.Names}}' | grep -qx netdata || fail "container netdata nao esta rodando"

echo "==> ok"
result "ok" "netdata rodando (acesse via tunel SSH)" "{\"url\":\"http://127.0.0.1:19999\"}"
