package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallZabbix runs the Zabbix stack (Postgres + zabbix-server +
// zabbix-web, 3 containers on their own docker network). The heaviest
// extra in the group — requires Docker (installed automatically if
// missing).
func InstallZabbix(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.ZabbixInstall), nil, env, onLine)
}
