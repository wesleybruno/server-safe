package modules

import (
	"context"
	"fmt"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type AutoUpdatesRequest struct {
	AutoReboot bool   `json:"auto_reboot"`
	RebootTime string `json:"reboot_time,omitempty"` // "HH:MM", default "04:00"
}

// EnableAutoUpdates configures unattended security updates (unattended-
// upgrades on Debian/Ubuntu, dnf-automatic on RHEL/Fedora).
func EnableAutoUpdates(ctx context.Context, req AutoUpdatesRequest, onLine func(string)) (*runner.Result, error) {
	rebootTime := req.RebootTime
	if rebootTime == "" {
		rebootTime = "04:00"
	}
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		fmt.Sprintf("SS_AUTO_REBOOT=%t", req.AutoReboot),
		"SS_REBOOT_TIME=" + rebootTime,
	}
	return runner.Run(ctx, scripts.Combine(scripts.AutoUpdates), nil, env, onLine)
}
