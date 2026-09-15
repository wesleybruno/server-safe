package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallSignoz runs the SigNoz observability stack via foundryctl (its
// official CLI). Requires Docker (installed automatically if missing).
func InstallSignoz(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"}
	return runner.Run(ctx, scripts.Combine(scripts.SignozInstall), nil, env, onLine)
}
