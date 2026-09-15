package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallNodeExporter runs Prometheus's node_exporter — host-level metrics
// (CPU/mem/disk/network) for scraping. Requires Docker (installed
// automatically if missing).
func InstallNodeExporter(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.NodeExporterInstall), nil, env, onLine)
}
