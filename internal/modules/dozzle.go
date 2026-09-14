package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallDozzle runs the official Dozzle container — a real-time log
// viewer for Docker containers. Requires Docker (installed automatically
// if missing).
func InstallDozzle(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.DozzleInstall), nil, env, onLine)
}
