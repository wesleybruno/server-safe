package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallCoolify runs Coolify's official installer (cdn.coollabs.io), which
// installs Docker itself if missing.
func InstallCoolify(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.CoolifyInstall), nil, env, onLine)
}
