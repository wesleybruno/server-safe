package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// ReadDashboardStats samples CPU/memory/disk usage once (~0.2s, dominated by
// the CPU sampling interval). Unlike the wizard step modules this is a
// read-only, always-available call — no onLine, log lines are discarded.
func ReadDashboardStats(ctx context.Context) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.DashboardStats), nil, env, nil)
}
