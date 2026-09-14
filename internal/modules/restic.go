package modules

import (
	"context"
	"strings"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type ResticRequest struct {
	Repo     string `json:"repo"`               // qualquer sintaxe de repositorio do restic (path local, sftp:, s3:, ...)
	Paths    string `json:"paths"`              // absolute paths, comma-separated
	Schedule string `json:"schedule,omitempty"` // systemd OnCalendar, default "daily"
}

// SetupRestic installs restic, initializes the repository if needed, and
// schedules a daily (or custom) backup + prune via a systemd timer.
func SetupRestic(ctx context.Context, req ResticRequest, onLine func(string)) (*runner.Result, error) {
	schedule := req.Schedule
	if schedule == "" {
		schedule = "daily"
	}
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		"SS_RESTIC_REPO=" + strings.TrimSpace(req.Repo),
		"SS_RESTIC_PATHS=" + req.Paths,
		"SS_RESTIC_SCHEDULE=" + schedule,
	}
	return runner.Run(ctx, scripts.Combine(scripts.ResticSetup), nil, env, onLine)
}
