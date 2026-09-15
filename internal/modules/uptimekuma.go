package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallUptimeKuma runs the official Uptime Kuma container — self-hosted
// uptime monitoring. Requires Docker (installed automatically if missing).
func InstallUptimeKuma(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.UptimeKumaInstall), nil, env, onLine)
}
