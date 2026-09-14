package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type AppTimerRequest struct {
	Name       string `json:"name"`
	Command    string `json:"command"`
	OnCalendar string `json:"on_calendar"` // ex: "daily", "*-*-* 04:00:00"
}

// CreateAppTimer generates a systemd .service/.timer pair that runs Command
// on the given OnCalendar schedule (e.g. periodic app restarts).
func CreateAppTimer(ctx context.Context, req AppTimerRequest, onLine func(string)) (*runner.Result, error) {
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		"SS_TIMER_NAME=" + req.Name,
		"SS_COMMAND=" + req.Command,
		"SS_ON_CALENDAR=" + req.OnCalendar,
	}
	return runner.Run(ctx, scripts.Combine(scripts.SystemdTimer), nil, env, onLine)
}
