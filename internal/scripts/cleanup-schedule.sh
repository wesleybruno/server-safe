# Schedules the final self-destruct: stop/remove the server-safe service and
# wipe leftover install files, a short delay after this HTTP response has
# already been sent (so the browser gets its confirmation first).
DELAY="${SS_DELAY:-5min}"
PATHS="${SS_PATHS:-}"
SELF_DESTRUCT="${SS_SELF_DESTRUCT:-true}"
STOP_CONTAINERS="${SS_STOP_CONTAINERS:-false}"
REMOVE_IMAGES="${SS_REMOVE_IMAGES:-false}"

# Docker cleanup roda na hora (sincrono, log ao vivo) — diferente do
# self-destruct do proprio painel, que fica agendado com atraso. Remover
# imagem exige que nenhum container (nem parado) esteja usando ela, entao
# "remover imagens" tambem para+remove todos os containers — nao da pra
# fazer so a parte de imagem sem isso. Nao mexe em volumes/networks: dados
# de containers (ex: historico do Zabbix, dashboards do Grafana) sobrevivem
# pra quem for reinstalar depois.
if [[ "$REMOVE_IMAGES" == "true" ]]; then
  if command -v docker &>/dev/null; then
    echo "==> parando e removendo todos os containers docker"
    docker ps -aq | xargs -r docker rm -f || true
    echo "==> removendo todas as imagens docker"
    docker images -aq | xargs -r docker rmi -f || true
  else
    echo "==> docker nao instalado, nada para limpar"
  fi
elif [[ "$STOP_CONTAINERS" == "true" ]]; then
  if command -v docker &>/dev/null; then
    echo "==> parando todos os containers docker em execucao"
    docker ps -q | xargs -r docker stop || true
  else
    echo "==> docker nao instalado, nada para parar"
  fi
fi

IFS=',' read -ra PATH_LIST <<< "$PATHS"
CLEAN_PATHS_ARR=()
for p in "${PATH_LIST[@]}"; do
  p_trim=$(echo "$p" | xargs)
  [[ -n "$p_trim" ]] || continue
  [[ "$p_trim" == /* ]] || fail "path nao absoluto recusado: $p_trim"
  CLEAN_PATHS_ARR+=("$p_trim")
done

CMD_PARTS=()
if [[ "$SELF_DESTRUCT" == "true" ]]; then
  CMD_PARTS+=("systemctl disable --now server-safe 2>/dev/null || true")
  CMD_PARTS+=("rm -f /etc/systemd/system/server-safe.service")
  CMD_PARTS+=("systemctl daemon-reload")
fi
if [[ ${#CLEAN_PATHS_ARR[@]} -gt 0 ]]; then
  QUOTED=""
  for p in "${CLEAN_PATHS_ARR[@]}"; do
    QUOTED+=$(printf ' %q' "$p")
  done
  CMD_PARTS+=("rm -f --$QUOTED")
fi

# Nada pra agendar (sem self-destruct, sem paths) nao e mais erro por si so
# — a limpeza docker acima (se pedida) ja e trabalho real feito de verdade.
# So falha se ABSOLUTAMENTE nada foi pedido.
if [[ ${#CMD_PARTS[@]} -eq 0 ]]; then
  if [[ "$STOP_CONTAINERS" != "true" && "$REMOVE_IMAGES" != "true" ]]; then
    fail "nada para fazer (sem self-destruct, sem paths, sem limpeza docker)"
  fi
  echo "==> ok"
  result "ok" "limpeza docker feita, nada agendado (sem self-destruct nem paths)" "{\"self_destruct\":false,\"stopped_containers\":$STOP_CONTAINERS,\"removed_images\":$REMOVE_IMAGES}"
  exit 0
fi

FULL_CMD=$(printf '%s; ' "${CMD_PARTS[@]}")

if command -v systemd-run &>/dev/null; then
  echo "==> agendando limpeza final via systemd-run em $DELAY"
  systemd-run --on-active="$DELAY" --unit=server-safe-cleanup --description="server-safe cleanup" \
    /bin/bash -c "$FULL_CMD"
elif command -v at &>/dev/null; then
  echo "==> systemd-run indisponivel, agendando via at"
  printf '%s\n' "$FULL_CMD" | at now + "$DELAY" 2>/dev/null || fail "falha ao agendar via at"
else
  fail "nem systemd-run nem at disponiveis — rode manualmente depois: $FULL_CMD"
fi

echo "==> ok"
result "ok" "limpeza final agendada em $DELAY" "{\"delay\":\"$DELAY\",\"self_destruct\":$SELF_DESTRUCT,\"stopped_containers\":$STOP_CONTAINERS,\"removed_images\":$REMOVE_IMAGES}"
