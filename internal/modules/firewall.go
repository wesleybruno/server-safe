package modules

import (
	"context"
	"fmt"
	"strings"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type FirewallRequest struct {
	SSHPort    int    `json:"ssh_port"`
	ExtraPorts string `json:"extra_ports,omitempty"` // ex: "80/tcp,443/tcp"
}

// EnableFirewall turns on UFW with a default-deny policy, allowing the SSH
// port (and any extra ports) first. Refuses to run if sshd is not already
// listening on SSHPort, to avoid locking the admin out.
func EnableFirewall(ctx context.Context, req FirewallRequest, onLine func(string)) (*runner.Result, error) {
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		fmt.Sprintf("SS_SSH_PORT=%d", req.SSHPort),
	}
	if strings.TrimSpace(req.ExtraPorts) != "" {
		env = append(env, "SS_EXTRA_PORTS="+req.ExtraPorts)
	}
	return runner.Run(ctx, scripts.Combine(scripts.FirewallUFW), nil, env, onLine)
}
