# Idempotent: reinicializa so se o repo ainda nao existir, reescreve o
# timer sempre (agenda/paths podem ter mudado). Repositorio generico —
# aceita qualquer sintaxe que o restic entenda (path local, sftp:, s3:,
# b2:, ...), sem UI dedicada por backend: o admin digita a string do
# restic direto, evita reinventar config por provedor aqui.
: "${SS_RESTIC_REPO:?missing SS_RESTIC_REPO}"
: "${SS_RESTIC_PATHS:?missing SS_RESTIC_PATHS}"
SCHEDULE="${SS_RESTIC_SCHEDULE:-daily}"

ensure_installed restic restic

IFS=',' read -ra PATH_LIST <<< "$SS_RESTIC_PATHS"
CLEAN_PATHS=()
for p in "${PATH_LIST[@]}"; do
  p_trim=$(echo "$p" | xargs)
  [[ -n "$p_trim" ]] || continue
  [[ "$p_trim" == /* ]] || fail "path nao absoluto recusado: $p_trim"
  CLEAN_PATHS+=("$p_trim")
done
[[ ${#CLEAN_PATHS[@]} -gt 0 ]] || fail "nenhum path valido pra backup"

PASSWORD_FILE=/etc/restic/password
PASSWORD=""

mkdir -p /etc/restic
chmod 700 /etc/restic

if [[ -s "$PASSWORD_FILE" ]]; then
  echo "==> senha do repositorio ja existe, reaproveitando"
else
  PASSWORD=$(random_password)
  printf '%s' "$PASSWORD" > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
  echo "==> senha do repositorio restic gerada (veja o campo na UI — nao e reexibida depois)"
fi

echo "==> verificando repositorio"
if restic -r "$SS_RESTIC_REPO" --password-file "$PASSWORD_FILE" snapshots &>/dev/null; then
  echo "==> repositorio ja inicializado"
else
  echo "==> inicializando repositorio restic em $SS_RESTIC_REPO"
  restic -r "$SS_RESTIC_REPO" --password-file "$PASSWORD_FILE" init \
    || fail "nao consegui inicializar o repositorio restic — confira o destino ($SS_RESTIC_REPO) e credenciais de acesso"
fi

UNIT_NAME=server-safe-restic-backup
WRAPPER_SCRIPT=/etc/restic/backup.sh
SERVICE_FILE="/etc/systemd/system/$UNIT_NAME.service"
TIMER_FILE="/etc/systemd/system/$UNIT_NAME.timer"

QUOTED_PATHS=""
for p in "${CLEAN_PATHS[@]}"; do
  QUOTED_PATHS+=$(printf ' %q' "$p")
done

# Comandos vao num script wrapper, nao direto no ExecStart= — %q gera
# quoting valido pra bash (que roda o wrapper), mas o parser de linha do
# proprio systemd pra ExecStart e mais simples que o do bash e nao entende
# a mesma sintaxe; embutir direto quebraria com paths/repo com espaco ou
# caractere especial.
echo "==> escrevendo script de backup em $WRAPPER_SCRIPT"
{
  echo "#!/usr/bin/env bash"
  echo "set -euo pipefail"
  echo "/usr/bin/restic -r $(printf '%q' "$SS_RESTIC_REPO") --password-file $PASSWORD_FILE backup$QUOTED_PATHS"
  # forget --prune com retencao fixa (7 diarios / 4 semanais / 6 mensais) —
  # nao exposto como opcao na UI de proposito, mantem o card simples; quem
  # precisar de outra politica ajusta o wrapper na mao depois.
  echo "/usr/bin/restic -r $(printf '%q' "$SS_RESTIC_REPO") --password-file $PASSWORD_FILE forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6"
} > "$WRAPPER_SCRIPT"
chmod 700 "$WRAPPER_SCRIPT"

echo "==> escrevendo unit $UNIT_NAME"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=server-safe managed restic backup

[Service]
Type=oneshot
ExecStart=$WRAPPER_SCRIPT
EOF

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=server-safe managed restic backup timer

[Timer]
OnCalendar=$SCHEDULE
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "$UNIT_NAME.timer"

echo "==> validando"
systemctl is-enabled "$UNIT_NAME.timer" &>/dev/null || fail "timer de backup nao habilitado"

echo "==> ok"
result "ok" "backup restic configurado (agenda: $SCHEDULE)" "{\"repo\":\"$(json_escape "$SS_RESTIC_REPO")\",\"schedule\":\"$(json_escape "$SCHEDULE")\",\"password\":\"$(json_escape "$PASSWORD")\"}"
