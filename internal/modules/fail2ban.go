package modules

import (
	"context"
	"fmt"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type Fail2banRequest struct {
	SSHPort  int `json:"ssh_port"`
	BanTime  int `json:"ban_time,omitempty"`  // segundos, default 3600
	FindTime int `json:"find_time,omitempty"` // segundos, default 600
	MaxRetry int `json:"max_retry,omitempty"` // default 5
}

// EnableFail2ban installs fail2ban and configures the sshd jail for the
// given port.
func EnableFail2ban(ctx context.Context, req Fail2banRequest, onLine func(string)) (*runner.Result, error) {
	if req.BanTime <= 0 {
		req.BanTime = 3600
	}
	if req.FindTime <= 0 {
		req.FindTime = 600
	}
	if req.MaxRetry <= 0 {
		req.MaxRetry = 5
	}
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		fmt.Sprintf("SS_SSH_PORT=%d", req.SSHPort),
		fmt.Sprintf("SS_BANTIME=%d", req.BanTime),
		fmt.Sprintf("SS_FINDTIME=%d", req.FindTime),
		fmt.Sprintf("SS_MAXRETRY=%d", req.MaxRetry),
	}
	return runner.Run(ctx, scripts.Combine(scripts.Fail2ban), nil, env, onLine)
}
