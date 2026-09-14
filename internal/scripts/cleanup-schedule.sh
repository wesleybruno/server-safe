# Schedules the final self-destruct: stop/remove the server-safe service and
# wipe leftover install files, a short delay after this HTTP response has
# already been sent (so the browser gets its confirmation first).
DELAY="${SS_DELAY:-5min}"
PATHS="${SS_PATHS:-}"
SELF_DESTRUCT="${SS_SELF_DESTRUCT:-true}"

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

[[ ${#CMD_PARTS[@]} -gt 0 ]] || fail "nada para agendar (sem paths e sem self-destruct)"

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
result "ok" "limpeza final agendada em $DELAY" "{\"delay\":\"$DELAY\",\"self_destruct\":$SELF_DESTRUCT}"
