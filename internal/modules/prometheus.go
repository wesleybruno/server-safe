package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallPrometheus runs the official Prometheus container with a minimal
// self-scrape config. Requires Docker (installed automatically if
// missing).
func InstallPrometheus(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.PrometheusInstall), nil, env, onLine)
}
