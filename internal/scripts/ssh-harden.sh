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

# Garante que o ssh sobe sozinho no proximo boot. Sem isso, um reboot
# (ex: atualizacao de kernel) pode deixar o servidor sem sshd e so o
# rescue mode do provedor resolve (incidente iestoque 2026-04-22).
# is-enabled aceita enabled/static/indirect/alias: static = sem [Install]
# proprio, mas puxado por outra unit (caso do ssh.socket em algumas
# imagens), tambem sobe no boot.
boot_enabled() {
  case "$(systemctl is-enabled "$1" 2>/dev/null)" in
    enabled|static|indirect|alias) return 0 ;;
    *) return 1 ;;
  esac
}

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
  if ! boot_enabled "$SSH_UNIT.socket"; then
    echo "==> habilitando $SSH_UNIT.socket no boot"
    systemctl enable "$SSH_UNIT.socket" 2>&1 || true
  fi
  echo "==> reiniciando $SSH_UNIT.socket"
  systemctl restart "$SSH_UNIT.socket"
  BOOT_UNIT="$SSH_UNIT.socket"
else
  if ! boot_enabled "$SSH_UNIT.service"; then
    echo "==> habilitando $SSH_UNIT.service no boot"
    systemctl enable "$SSH_UNIT.service" 2>&1 || true
  fi
  # restart (nao reload): reload nao reabre o listener socket na porta nova.
  # conexoes ja estabelecidas continuam ativas durante o restart.
  echo "==> reiniciando $SSH_UNIT.service"
  systemctl restart "$SSH_UNIT.service"
  BOOT_UNIT="$SSH_UNIT.service"
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

if boot_enabled "$BOOT_UNIT" || boot_enabled "$SSH_UNIT.service"; then
  echo "==> $BOOT_UNIT habilitado no boot"
else
  fail "$BOOT_UNIT nao esta habilitado no boot — um reboot deixaria o servidor sem ssh. Rode: systemctl enable $BOOT_UNIT"
fi

# Dados pra guardar FORA do servidor: o incidente de 2026-04-22 levou ~1h
# a mais porque porta/usuario nao estavam anotados e nao havia como saber
# se a host key mudou de forma legitima. Fingerprints das host keys
# permitem conferir um "REMOTE HOST IDENTIFICATION HAS CHANGED" depois.
HOST_KEYS=""
for pub in /etc/ssh/ssh_host_*_key.pub; do
  [[ -f "$pub" ]] || continue
  fp=$(ssh-keygen -lf "$pub" 2>/dev/null) || continue
  HOST_KEYS+="$fp"$'\n'
done
HOST_KEYS="${HOST_KEYS%$'\n'}"
# Primeiro IP global da interface de saida — numa VPS (Hetzner etc.) e o
# IP publico. Atras de NAT pode ser IP privado; a UI deixa claro que e o
# "IP detectado".
SERVER_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)
[[ -n "$SERVER_IP" ]] || SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)

echo "==> fingerprints das host keys (guarde fora do servidor):"
echo "$HOST_KEYS"

echo "==> ok, ssh escutando na porta $SS_NEW_PORT"
result "ok" "ssh hardened na porta $SS_NEW_PORT" "{\"port\":$SS_NEW_PORT,\"password_disabled\":$DISABLE_PASSWORD,\"root_disabled\":$DISABLE_ROOT,\"server_ip\":\"$(json_escape "$SERVER_IP")\",\"host_keys\":\"$(json_escape "$HOST_KEYS")\"}"
