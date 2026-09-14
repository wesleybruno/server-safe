# Idempotent: ufw dedupes repeated allow rules and re-enable is a no-op.
: "${SS_SSH_PORT:?missing SS_SSH_PORT}"
EXTRA_PORTS="${SS_EXTRA_PORTS:-}"

echo "==> verificando se sshd ja escuta na porta $SS_SSH_PORT antes de mexer no firewall"
if ! ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${SS_SSH_PORT}\$"; then
  fail "sshd nao esta escutando na porta $SS_SSH_PORT — abortando (evita lockout). Rode o step SSH antes deste."
fi

ensure_installed ufw ufw ufw

echo "==> configurando politica padrao (deny incoming, allow outgoing)"
ufw default deny incoming
ufw default allow outgoing

echo "==> liberando porta ssh $SS_SSH_PORT/tcp"
ufw allow "$SS_SSH_PORT"/tcp

if [[ -n "$EXTRA_PORTS" ]]; then
  IFS=',' read -ra PORTS <<< "$EXTRA_PORTS"
  for p in "${PORTS[@]}"; do
    p_trim=$(echo "$p" | xargs)
    [[ -n "$p_trim" ]] || continue
    echo "==> liberando $p_trim"
    ufw allow "$p_trim"
  done
fi

echo "==> ativando ufw"
ufw --force enable

echo "==> validando"
ufw status | grep -qi "Status: active" || fail "ufw nao ficou ativo"
ufw status | grep -q "$SS_SSH_PORT/tcp" || fail "regra da porta ssh nao esta ativa"

echo "==> ok"
result "ok" "firewall ativo, porta ssh $SS_SSH_PORT liberada" "{\"ssh_port\":$SS_SSH_PORT}"
