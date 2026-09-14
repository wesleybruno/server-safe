# Idempotent: overwrites unit files with the same name, safe to re-run.
# SS_COMMAND runs as root via this locally-served, root-only wizard — same
# trust boundary as the admin typing it directly in a root shell.
: "${SS_TIMER_NAME:?missing SS_TIMER_NAME}"
: "${SS_COMMAND:?missing SS_COMMAND}"
: "${SS_ON_CALENDAR:?missing SS_ON_CALENDAR}"

if [[ ! "$SS_TIMER_NAME" =~ ^[a-zA-Z0-9_-]{1,64}$ ]]; then
  fail "nome de timer invalido: $SS_TIMER_NAME"
fi

UNIT_NAME="server-safe-$SS_TIMER_NAME"
SERVICE_FILE="/etc/systemd/system/$UNIT_NAME.service"
TIMER_FILE="/etc/systemd/system/$UNIT_NAME.timer"

echo "==> escrevendo unit $UNIT_NAME"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=server-safe managed timer: $SS_TIMER_NAME

[Service]
Type=oneshot
ExecStart=/bin/bash -lc "$SS_COMMAND"
EOF

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=server-safe managed timer: $SS_TIMER_NAME

[Timer]
OnCalendar=$SS_ON_CALENDAR
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "$UNIT_NAME.timer"

echo "==> validando"
systemctl is-enabled "$UNIT_NAME.timer" &>/dev/null || fail "timer nao habilitado"

echo "==> ok"
result "ok" "timer $UNIT_NAME ativo" "{\"unit\":\"$UNIT_NAME\",\"on_calendar\":\"$SS_ON_CALENDAR\"}"
