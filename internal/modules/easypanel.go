package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallEasyPanel runs EasyPanel's official installer (get.easypanel.io),
// which installs Docker itself if missing.
func InstallEasyPanel(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.EasyPanelInstall), nil, env, onLine)
}
