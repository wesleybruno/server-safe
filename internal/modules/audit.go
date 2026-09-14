package modules

import (
	"context"
	"fmt"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type SecurityAuditRequest struct {
	SSHPort int `json:"ssh_port,omitempty"`
}

// RunSecurityAudit checks the applied hardening plus general posture
// (open ports, sudoers, UID 0 accounts, key permissions, optional lynis)
// and returns a pass/warn/fail count with a full text report in Data.
func RunSecurityAudit(ctx context.Context, req SecurityAuditRequest, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	if req.SSHPort > 0 {
		env = append(env, fmt.Sprintf("SS_SSH_PORT=%d", req.SSHPort))
	}
	return runner.Run(ctx, scripts.Combine(scripts.SecurityAudit), nil, env, onLine)
}
