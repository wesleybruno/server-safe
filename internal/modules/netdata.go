package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallNetdata runs Netdata — real-time system monitoring dashboard
// (CPU/mem/disk/network). Requires Docker (installed automatically if
// missing).
func InstallNetdata(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.NetdataInstall), nil, env, onLine)
}
