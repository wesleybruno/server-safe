# Idempotent: overwrites its own config drop-in, safe to re-run.
AUTO_REBOOT="${SS_AUTO_REBOOT:-false}"
REBOOT_TIME="${SS_REBOOT_TIME:-04:00}"

FAMILY=$(distro_family)

if [[ "$FAMILY" == "debian" ]]; then
  ensure_installed unattended-upgrade unattended-upgrades
  echo "==> configurando unattended-upgrades"
  cat > /etc/apt/apt.conf.d/51server-safe <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
  if [[ "$AUTO_REBOOT" == "true" ]]; then
    cat >> /etc/apt/apt.conf.d/51server-safe <<EOF
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "$REBOOT_TIME";
EOF
  fi
  systemctl enable --now unattended-upgrades 2>/dev/null || true
  echo "==> validando"
  systemctl is-enabled unattended-upgrades &>/dev/null || fail "unattended-upgrades nao habilitado"
else
  ensure_installed dnf-automatic dnf-automatic
  echo "==> configurando dnf-automatic"
  sed -i 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
  if [[ "$AUTO_REBOOT" == "true" ]]; then
    echo "==> aviso: reboot automatico no dnf-automatic requer configuracao manual adicional, pulando"
  fi
  systemctl enable --now dnf-automatic.timer
  echo "==> validando"
  systemctl is-enabled dnf-automatic.timer &>/dev/null || fail "dnf-automatic.timer nao habilitado"
fi

echo "==> ok"
result "ok" "atualizacoes automaticas de seguranca ativas" "{\"family\":\"$FAMILY\",\"auto_reboot\":$AUTO_REBOOT}"
