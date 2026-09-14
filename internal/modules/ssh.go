package modules

import (
	"context"
	"fmt"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type HardenSSHRequest struct {
	Port            int    `json:"port"`
	DisablePassword bool   `json:"disable_password"`
	DisableRoot     bool   `json:"disable_root"`
	AllowUsers      string `json:"allow_users,omitempty"`
}

// HardenSSH writes a drop-in sshd config (new port, optional password/root
// login lockout) and restarts sshd, validating both the config syntax and
// the effective running state before reporting success.
func HardenSSH(ctx context.Context, req HardenSSHRequest, onLine func(string)) (*runner.Result, error) {
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		fmt.Sprintf("SS_NEW_PORT=%d", req.Port),
		fmt.Sprintf("SS_DISABLE_PASSWORD=%t", req.DisablePassword),
		fmt.Sprintf("SS_DISABLE_ROOT=%t", req.DisableRoot),
	}
	if req.AllowUsers != "" {
		env = append(env, "SS_ALLOW_USERS="+req.AllowUsers)
	}
	return runner.Run(ctx, scripts.Combine(scripts.SSHHarden), nil, env, onLine)
}
