package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallCPanel runs cPanel/WHM's official installer. Only AlmaLinux/
// CloudLinux/RHEL are supported (the script itself checks and fails fast
// otherwise); requires a paid license and takes 1-2h.
func InstallCPanel(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.CPanelInstall), nil, env, onLine)
}
