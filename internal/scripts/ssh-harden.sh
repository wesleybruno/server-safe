# Idempotent: overwrites its own drop-in config file, safe to re-run.

: "${SS_NEW_PORT:?missing SS_NEW_PORT}"
DISABLE_PASSWORD="${SS_DISABLE_PASSWORD:-false}"
DISABLE_ROOT="${SS_DISABLE_ROOT:-false}"
ALLOW_USERS="${SS_ALLOW_USERS:-}"

if ! [[ "$SS_NEW_PORT" =~ ^[0-9]+$ ]] || (( SS_NEW_PORT < 1 || SS_NEW_PORT > 65535 )); then
  fail "porta invalida: $SS_NEW_PORT"
fi

if [[ "$DISABLE_PASSWORD" == "true" ]]; then
  # Anti-lockout tecnico: sem pelo menos uma chave publica instalada em
  # algum usuario sudo/wheel (ou root), desativar login por senha agora
  # trancaria todo mundo fora — nem chave, nem senha. Isso nao depende do
  # checkbox "ja testei a chave" da UI (autodeclarado); aqui e checagem
  # real do estado do sistema. Roda antes do wizard ter uma etapa
  # dedicada de "usuario" ser obrigatoria, ja que agora todas as etapas
  # ficam acessiveis sem ordem forcada.
  SUDO_GROUP=""
  if getent group sudo &>/dev/null; then
    SUDO_GROUP="sudo"
  elif getent group wheel &>/dev/null; then
    SUDO_GROUP="wheel"
  fi
  HAS_KEY="false"
  if [[ -n "$SUDO_GROUP" ]]; then
    for u in $(getent group "$SUDO_GROUP" | cut -d: -f4 | tr ',' ' '); do
      home=$(getent passwd "$u" 2>/dev/null | cut -d: -f6)
      if [[ -n "$home" && -s "$home/.ssh/authorized_keys" ]]; then
        HAS_KEY="true"
        break
      fi
    done
  fi
  if [[ "$HAS_KEY" != "true" && -s /root/.ssh/authorized_keys ]]; then
    HAS_KEY="true"
  fi
  [[ "$HAS_KEY" == "true" ]] || fail "nenhum usuario sudo/wheel (nem root) tem chave publica em authorized_keys — desativar login por senha agora te trancaria fora. Rode a etapa 'Usuario e chave SSH' antes."
fi

MAIN_CONFIG="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
# 00- (nao 99-): dentro de sshd_config.d, a *primeira* ocorrencia de uma
# diretiva vence, nao a ultima (ao contrario da maioria dos formatos de
# config, e do jail.d do fail2ban). Um 99- so ganharia se nenhum outro
# arquivo do diretorio setasse a mesma diretiva antes — imagens Ubuntu com
# cloud-init costumam trazer um 50-cloud-init.conf com PasswordAuthentication
# explicito, que silenciosamente vencia o nosso.
DROPIN_FILE="$DROPIN_DIR/00-server-safe.conf"
rm -f "$DROPIN_DIR/99-server-safe.conf" # limpa nome antigo de versoes anteriores

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
