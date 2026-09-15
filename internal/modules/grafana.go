package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallGrafana runs the official Grafana container. Requires Docker
// (installed automatically if missing).
func InstallGrafana(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.GrafanaInstall), nil, env, onLine)
}
