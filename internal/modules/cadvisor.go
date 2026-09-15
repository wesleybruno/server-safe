package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallCadvisor runs Google's cAdvisor container — per-container
// resource usage metrics. Requires Docker (installed automatically if
// missing).
func InstallCadvisor(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.CadvisorInstall), nil, env, onLine)
}
