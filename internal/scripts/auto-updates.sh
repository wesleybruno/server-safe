# Idempotent: overwrites its own config drop-in and reboot-window units,
# safe to re-run.
#
# Reboot automatico NUNCA usa o Automatic-Reboot diario do unattended-
# upgrades: ele reinicia no primeiro horario depois de qualquer update de
# kernel, sem janela planejada — foi isso que derrubou servicos (Swarm nao
# reconciliou no boot) por 9h sem ninguem notar no incidente iestoque
# 2026-05-21. Em vez disso: timer semanal proprio (dia + horario) que so
# reinicia se alguma atualizacao exigir reboot.
AUTO_REBOOT="${SS_AUTO_REBOOT:-false}"
REBOOT_DAY="${SS_REBOOT_DAY:-Sun}"
REBOOT_TIME="${SS_REBOOT_TIME:-04:00}"

case "$REBOOT_DAY" in
  Mon|Tue|Wed|Thu|Fri|Sat|Sun) ;;
  *) fail "dia de reboot invalido: $REBOOT_DAY (use Mon..Sun)" ;;
esac
[[ "$REBOOT_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || fail "horario de reboot invalido: $REBOOT_TIME (use HH:MM)"

FAMILY=$(distro_family)

if [[ "$FAMILY" == "debian" ]]; then
  ensure_installed unattended-upgrade unattended-upgrades
  echo "==> configurando unattended-upgrades"
  # Automatic-Reboot "false" explicito: 51- vem depois do 50unattended-
  # upgrades da distro e sobrescreve um "true" que esteja la.
  cat > /etc/apt/apt.conf.d/51server-safe <<CONF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
CONF
  systemctl enable --now unattended-upgrades 2>/dev/null || true
  echo "==> validando"
  systemctl is-enabled unattended-upgrades &>/dev/null || fail "unattended-upgrades nao habilitado"
else
  ensure_installed dnf-automatic dnf-automatic
  echo "==> configurando dnf-automatic"
  sed -i 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
  systemctl enable --now dnf-automatic.timer
  echo "==> validando"
  systemctl is-enabled dnf-automatic.timer &>/dev/null || fail "dnf-automatic.timer nao habilitado"
fi

UNIT_NAME=server-safe-reboot-window
REBOOT_SCRIPT=/usr/local/sbin/server-safe-reboot-window.sh
SERVICE_FILE="/etc/systemd/system/$UNIT_NAME.service"
TIMER_FILE="/etc/systemd/system/$UNIT_NAME.timer"

if [[ "$AUTO_REBOOT" == "true" ]]; then
  echo "==> configurando janela semanal de reboot: $REBOOT_DAY $REBOOT_TIME (so se necessario)"
  # Debian/Ubuntu: /var/run/reboot-required. RHEL: needs-restarting -r
  # (dnf-utils) sai com 1 quando precisa reiniciar. shutdown -r +5 (nao
  # now): avisa sessoes abertas e deixa 5 min pra cancelar (shutdown -c).
  cat > "$REBOOT_SCRIPT" <<'SCRIPT'
#!/usr/bin/env bash
# gerado por server-safe, nao editar manualmente
NEEDS=false
[[ -f /var/run/reboot-required ]] && NEEDS=true
if [[ "$NEEDS" == "false" ]] && command -v needs-restarting &>/dev/null; then
  needs-restarting -r &>/dev/null || NEEDS=true
fi
if [[ "$NEEDS" == "true" ]]; then
  echo "server-safe: atualizacao exige reboot, reiniciando na janela semanal"
  /sbin/shutdown -r +5 "server-safe: reboot da janela semanal (atualizacoes pendentes). Cancelar: shutdown -c"
else
  echo "server-safe: nenhum reboot pendente, nada a fazer"
fi
SCRIPT
  chmod 755 "$REBOOT_SCRIPT"

  cat > "$SERVICE_FILE" <<UNIT
[Unit]
Description=server-safe: reboot semanal se alguma atualizacao exigir

[Service]
Type=oneshot
ExecStart=$REBOOT_SCRIPT
UNIT

  # Persistent=false de proposito: se a maquina estava desligada na janela,
  # NAO reinicia ao ligar (isso seria um reboot fora da janela).
  cat > "$TIMER_FILE" <<UNIT
[Unit]
Description=server-safe: janela semanal de reboot

[Timer]
OnCalendar=$REBOOT_DAY *-*-* $REBOOT_TIME:00
Persistent=false

[Install]
WantedBy=timers.target
UNIT

  systemctl daemon-reload
  systemctl enable --now "$UNIT_NAME.timer"
  systemctl is-enabled "$UNIT_NAME.timer" &>/dev/null || fail "timer da janela de reboot nao habilitado"
  NEXT=$(systemctl list-timers "$UNIT_NAME.timer" --no-legend 2>/dev/null | awk '{print $1, $2, $3}' || true)
  echo "==> proxima janela de reboot: ${NEXT:-desconhecida}"
else
  # Reboot automatico desligado: remove janela criada por execucao anterior.
  if [[ -f "$TIMER_FILE" ]]; then
    echo "==> removendo janela de reboot configurada antes"
    systemctl disable --now "$UNIT_NAME.timer" 2>/dev/null || true
    rm -f "$TIMER_FILE" "$SERVICE_FILE" "$REBOOT_SCRIPT"
    systemctl daemon-reload
  fi
fi

WINDOW=""
[[ "$AUTO_REBOOT" == "true" ]] && WINDOW="$REBOOT_DAY $REBOOT_TIME"

echo "==> ok"
result "ok" "atualizacoes automaticas de seguranca ativas" "{\"family\":\"$FAMILY\",\"auto_reboot\":$AUTO_REBOOT,\"reboot_window\":\"$WINDOW\"}"
