// Package scripts embeds the bash modules directly into the binary so the
// compiled server carries every hardening script with it — nothing to
// extract to disk, no dependency on the target machine's filesystem layout.
package scripts

import (
	"bytes"
	_ "embed"
)

//go:embed common.sh
var Common []byte

//go:embed user-create.sh
var UserCreate []byte

//go:embed ssh-harden.sh
var SSHHarden []byte

//go:embed firewall-ufw.sh
var FirewallUFW []byte

//go:embed fail2ban-setup.sh
var Fail2ban []byte

//go:embed auto-updates.sh
var AutoUpdates []byte

//go:embed systemd-timer.sh
var SystemdTimer []byte

//go:embed security-audit.sh
var SecurityAudit []byte

//go:embed docker-install.sh
var DockerInstall []byte

//go:embed portainer-install.sh
var PortainerInstall []byte

//go:embed traefik-install.sh
var TraefikInstall []byte

//go:embed coolify-install.sh
var CoolifyInstall []byte

//go:embed easypanel-install.sh
var EasyPanelInstall []byte

//go:embed cpanel-install.sh
var CPanelInstall []byte

//go:embed dozzle-install.sh
var DozzleInstall []byte

//go:embed restic-setup.sh
var ResticSetup []byte

//go:embed uptime-kuma-install.sh
var UptimeKumaInstall []byte

//go:embed cadvisor-install.sh
var CadvisorInstall []byte

//go:embed prometheus-install.sh
var PrometheusInstall []byte

//go:embed grafana-install.sh
var GrafanaInstall []byte

//go:embed loki-install.sh
var LokiInstall []byte

//go:embed zabbix-install.sh
var ZabbixInstall []byte

//go:embed signoz-install.sh
var SignozInstall []byte

//go:embed netdata-install.sh
var NetdataInstall []byte

//go:embed node-exporter-install.sh
var NodeExporterInstall []byte

//go:embed dashboard-stats.sh
var DashboardStats []byte

//go:embed cleanup-schedule.sh
var CleanupSchedule []byte

// Combine prefixes a module script with the shared helpers (result, fail,
// ensure_installed, ...) so both are fed to bash as a single stdin stream —
// no second file to source from disk.
func Combine(module []byte) []byte {
	return bytes.Join([][]byte{Common, module}, []byte("\n"))
}
