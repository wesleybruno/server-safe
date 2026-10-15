package modules

import (
	"context"
	"fmt"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type AutoUpdatesRequest struct {
	AutoReboot bool   `json:"auto_reboot"`
	RebootDay  string `json:"reboot_day,omitempty"`  // "Mon".."Sun", default "Sun"
	RebootTime string `json:"reboot_time,omitempty"` // "HH:MM", default "04:00"
}

// EnableAutoUpdates configures unattended security updates (unattended-
// upgrades on Debian/Ubuntu, dnf-automatic on RHEL/Fedora). Auto reboot,
// when enabled, is a weekly window (day + time) that only fires if an
// update actually requires it — never the distro's daily auto-reboot.
func EnableAutoUpdates(ctx context.Context, req AutoUpdatesRequest, onLine func(string)) (*runner.Result, error) {
	rebootTime := req.RebootTime
	if rebootTime == "" {
		rebootTime = "04:00"
	}
	rebootDay := req.RebootDay
	if rebootDay == "" {
		rebootDay = "Sun"
	}
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		fmt.Sprintf("SS_AUTO_REBOOT=%t", req.AutoReboot),
		"SS_REBOOT_DAY=" + rebootDay,
		"SS_REBOOT_TIME=" + rebootTime,
	}
	return runner.Run(ctx, scripts.Combine(scripts.AutoUpdates), nil, env, onLine)
}
