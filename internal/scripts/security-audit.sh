# Audits, does not harden. Intentionally continues past failing checks
# instead of aborting via fail() — relax common.sh's strict mode for that.
set +e +o pipefail

SSH_PORT="${SS_SSH_PORT:-}"

PASS=0
WARN=0
FAIL=0
REPORT=""

check() {
  # usage: check <label> <ok|warn|fail> <detail>
  local label="$1" status="$2" detail="$3"
  case "$status" in
    ok)   PASS=$((PASS+1)); echo "[OK]   $label - $detail" ;;
    warn) WARN=$((WARN+1)); echo "[WARN] $label - $detail" ;;
    fail) FAIL=$((FAIL+1)); echo "[FAIL] $label - $detail" ;;
  esac
  REPORT+="[$status] $label - $detail"$'\n'
}

echo "==> auditoria de seguranca"

# So porta amarrada em endereco nao-loopback conta como exposta pra fora —
# 127.x/[::1] (Portainer 9443, painel 8080, etc.) fica de fora de proposito:
# nao e alcancavel da rede de jeito nenhum, listar junto so gera ruido e faz
# parecer que precisa de acao quando nao precisa.
OPEN_PORTS=$(ss -tln 2>/dev/null | awk 'NR>1{print $4}' | grep -vE '^(127\.|\[::1\])' | sed -E 's/.*:([0-9]+)$/\1/' | sort -nu | tr '\n' ',' | sed 's/,$//')
if [[ -n "$OPEN_PORTS" ]]; then
  check "portas-expostas" "warn" "portas TCP em LISTEN alcancaveis de fora (nao-loopback): $OPEN_PORTS"
else
  check "portas-expostas" "ok" "nenhuma porta TCP exposta alem de loopback"
fi

if command -v sshd &>/dev/null; then
  EFFECTIVE=$(sshd -T 2>/dev/null)

  if echo "$EFFECTIVE" | grep -qi "^permitrootlogin no$"; then
    check "ssh-root-login" "ok" "PermitRootLogin no"
  else
    check "ssh-root-login" "fail" "login root via SSH nao esta desabilitado"
  fi

  if echo "$EFFECTIVE" | grep -qi "^passwordauthentication no$"; then
    check "ssh-password-auth" "ok" "PasswordAuthentication no"
  else
    check "ssh-password-auth" "warn" "login por senha ainda habilitado"
  fi

  if [[ -n "$SSH_PORT" ]]; then
    if echo "$EFFECTIVE" | grep -qi "^port $SSH_PORT\$"; then
      check "ssh-porta" "ok" "sshd escutando na porta esperada $SSH_PORT"
    else
      check "ssh-porta" "fail" "sshd nao esta na porta esperada $SSH_PORT"
    fi
  fi
else
  check "ssh" "warn" "sshd nao encontrado no PATH"
fi

if command -v ufw &>/dev/null; then
  if ufw status | grep -qi "Status: active"; then
    check "firewall" "ok" "ufw ativo"
  else
    check "firewall" "fail" "ufw instalado mas inativo"
  fi
else
  check "firewall" "fail" "ufw nao instalado"
fi

if command -v fail2ban-client &>/dev/null; then
  if systemctl is-active fail2ban &>/dev/null; then
    check "fail2ban" "ok" "fail2ban ativo"
  else
    check "fail2ban" "fail" "fail2ban instalado mas inativo"
  fi
else
  check "fail2ban" "fail" "fail2ban nao instalado"
fi

NOPASSWD_COUNT=$(grep -rEl 'NOPASSWD' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | wc -l)
if [[ "$NOPASSWD_COUNT" -gt 0 ]]; then
  check "sudo-nopasswd" "warn" "$NOPASSWD_COUNT arquivo(s) com entradas NOPASSWD em sudoers"
else
  check "sudo-nopasswd" "ok" "nenhuma entrada NOPASSWD encontrada"
fi

EXTRA_UID0=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
if [[ -n "$EXTRA_UID0" ]]; then
  check "uid-zero" "fail" "usuarios com UID 0 alem de root: $EXTRA_UID0"
else
  check "uid-zero" "ok" "nenhum usuario extra com UID 0"
fi

BAD_PERMS=""
while IFS=: read -r user _ _ _ _ home _; do
  [[ -d "$home/.ssh" ]] || continue
  perm=$(stat -c '%a' "$home/.ssh" 2>/dev/null)
  [[ "$perm" == "700" ]] || BAD_PERMS+="$user(.ssh=$perm) "
done < /etc/passwd
if [[ -n "$BAD_PERMS" ]]; then
  check "ssh-dir-perms" "warn" "permissao fora do padrao 700: $BAD_PERMS"
else
  check "ssh-dir-perms" "ok" "todos os .ssh com permissao 700"
fi

if systemctl is-enabled unattended-upgrades &>/dev/null || systemctl is-enabled dnf-automatic.timer &>/dev/null; then
  check "auto-updates" "ok" "atualizacoes automaticas habilitadas"
else
  check "auto-updates" "warn" "atualizacoes automaticas nao configuradas"
fi

if command -v lynis &>/dev/null; then
  echo "==> rodando lynis --quick (pode demorar um pouco)"
  LYNIS_OUT=$(lynis audit system --quick --no-colors 2>&1 | tail -n 40)
  REPORT+=$'\n'"--- lynis (ultimas linhas) ---"$'\n'"$LYNIS_OUT"$'\n'
  check "lynis" "ok" "lynis executado, ver relatorio completo em data.report"
else
  check "lynis" "warn" "lynis nao instalado, pulando auditoria estendida (opcional)"
fi

echo "==> resumo: $PASS ok, $WARN aviso(s), $FAIL falha(s)"

STATUS="ok"
[[ "$FAIL" -eq 0 ]] || STATUS="error"

ESCAPED_REPORT=$(json_escape "$REPORT")
result "$STATUS" "$PASS ok, $WARN aviso(s), $FAIL falha(s)" "{\"pass\":$PASS,\"warn\":$WARN,\"fail\":$FAIL,\"report\":\"$ESCAPED_REPORT\"}"
exit 0
