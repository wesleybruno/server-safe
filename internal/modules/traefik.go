package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallTraefik runs the official Traefik container as a reverse proxy.
// Requires Docker (fails fast with a clear message if it's not installed).
func InstallTraefik(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.TraefikInstall), nil, env, onLine)
}
