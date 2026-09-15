package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallLoki runs the official Loki container (log aggregation backend,
// meant to be queried through Grafana). Requires Docker (installed
// automatically if missing).
func InstallLoki(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.LokiInstall), nil, env, onLine)
}
