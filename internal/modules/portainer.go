package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallPortainer runs the official Portainer CE container. Requires
// Docker (fails fast with a clear message if it's not installed).
func InstallPortainer(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.PortainerInstall), nil, env, onLine)
}
