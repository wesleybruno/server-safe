# Idempotent: overwrites its own drop-in config file, safe to re-run.

: "${SS_NEW_PORT:?missing SS_NEW_PORT}"
DISABLE_PASSWORD="${SS_DISABLE_PASSWORD:-false}"
DISABLE_ROOT="${SS_DISABLE_ROOT:-false}"
ALLOW_USERS="${SS_ALLOW_USERS:-}"

if ! [[ "$SS_NEW_PORT" =~ ^[0-9]+$ ]] || (( SS_NEW_PORT < 1 || SS_NEW_PORT > 65535 )); then
  fail "porta invalida: $SS_NEW_PORT"
fi

MAIN_CONFIG="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
DROPIN_FILE="$DROPIN_DIR/99-server-safe.conf"

if ! grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' "$MAIN_CONFIG" 2>/dev/null; then
  echo "==> sshd_config nao inclui drop-ins automaticamente, adicionando Include"
  cp "$MAIN_CONFIG" "$MAIN_CONFIG.server-safe.bak" 2>/dev/null || true
  sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$MAIN_CONFIG"
fi

mkdir -p "$DROPIN_DIR"

echo "==> escrevendo config em $DROPIN_FILE"
{
  echo "# gerado por server-safe, nao editar manualmente"
  echo "Port $SS_NEW_PORT"
  if [[ "$DISABLE_PASSWORD" == "true" ]]; then
    echo "PasswordAuthentication no"
    echo "KbdInteractiveAuthentication no"
  fi
  if [[ "$DISABLE_ROOT" == "true" ]]; then
    echo "PermitRootLogin no"
  fi
  if [[ -n "$ALLOW_USERS" ]]; then
    echo "AllowUsers $ALLOW_USERS"
  fi
} > "$DROPIN_FILE"
chmod 600 "$DROPIN_FILE"

echo "==> validando config (sshd -t)"
if ! sshd -t 2>&1; then
  fail "sshd -t falhou, config nao aplicada"
fi

SSH_UNIT=""
for unit in ssh sshd; do
  if systemctl list-unit-files "$unit.service" --no-legend --plain 2>/dev/null | grep -q "^$unit\.service" \
    || systemctl list-unit-files "$unit.socket" --no-legend --plain 2>/dev/null | grep -q "^$unit\.socket"; then
    SSH_UNIT="$unit"
    break
  fi
done
[[ -n "$SSH_UNIT" ]] || fail "nao encontrei unit systemd do ssh (ssh/sshd)"

if systemctl list-unit-files "$SSH_UNIT.socket" --no-legend --plain 2>/dev/null | grep -q "^$SSH_UNIT\.socket"; then
  # Ubuntu 24.04+ ativa o sshd via socket activation por padrao: quem
  # escuta a porta e o $SSH_UNIT.socket (fica "static", nao "enabled"), o
  # .service so sobe por conexao — Port no sshd_config sozinho nao move o
  # bind, precisa sobrescrever o ListenStream do socket.
  echo "==> ssh ativado via socket ($SSH_UNIT.socket), ajustando ListenStream"
  mkdir -p "/etc/systemd/system/$SSH_UNIT.socket.d"
  {
    echo "[Socket]"
    echo "ListenStream="
    echo "ListenStream=$SS_NEW_PORT"
  } > "/etc/systemd/system/$SSH_UNIT.socket.d/99-server-safe.conf"
  systemctl daemon-reload
  echo "==> reiniciando $SSH_UNIT.socket"
  systemctl restart "$SSH_UNIT.socket"
else
  # restart (nao reload): reload nao reabre o listener socket na porta nova.
  # conexoes ja estabelecidas continuam ativas durante o restart.
  echo "==> reiniciando $SSH_UNIT.service"
  systemctl restart "$SSH_UNIT.service"
fi

sleep 1
echo "==> validando estado efetivo"
EFFECTIVE=$(sshd -T 2>/dev/null)
# valida a porta pelo listener real (ss), nao so pelo sshd -T — sob socket
# activation o bind e feito pelo systemd, sshd -T pode nao refletir isso.
ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${SS_NEW_PORT}\$" || fail "porta nova nao esta escutando (ss -tln)"

if [[ "$DISABLE_ROOT" == "true" ]]; then
  echo "$EFFECTIVE" | grep -qi "^permitrootlogin no$" || fail "permitrootlogin nao aplicado"
fi
if [[ "$DISABLE_PASSWORD" == "true" ]]; then
  echo "$EFFECTIVE" | grep -qi "^passwordauthentication no$" || fail "passwordauthentication nao aplicado"
fi

echo "==> ok, ssh escutando na porta $SS_NEW_PORT"
result "ok" "ssh hardened na porta $SS_NEW_PORT" "{\"port\":$SS_NEW_PORT,\"password_disabled\":$DISABLE_PASSWORD,\"root_disabled\":$DISABLE_ROOT}"
