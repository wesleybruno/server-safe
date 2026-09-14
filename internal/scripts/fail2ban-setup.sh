# Idempotent: overwrites its own jail.d drop-in, safe to re-run.
: "${SS_SSH_PORT:?missing SS_SSH_PORT}"
BANTIME="${SS_BANTIME:-3600}"
FINDTIME="${SS_FINDTIME:-600}"
MAXRETRY="${SS_MAXRETRY:-5}"

ensure_installed fail2ban-client fail2ban fail2ban

mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/99-server-safe.conf <<EOF
[sshd]
enabled = true
port = $SS_SSH_PORT
backend = systemd
bantime = $BANTIME
findtime = $FINDTIME
maxretry = $MAXRETRY
EOF

echo "==> habilitando e reiniciando fail2ban"
systemctl enable fail2ban
systemctl restart fail2ban

sleep 1
echo "==> validando jail sshd"
fail2ban-client status sshd &>/dev/null || fail "jail sshd nao esta ativo apos restart"

echo "==> ok"
result "ok" "fail2ban ativo, jail sshd na porta $SS_SSH_PORT" "{\"bantime\":$BANTIME,\"findtime\":$FINDTIME,\"maxretry\":$MAXRETRY}"
