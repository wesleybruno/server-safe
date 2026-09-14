package modules

import (
	"context"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

// InstallDocker installs Docker Engine from the official upstream repo
// (docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin) and
// enables the service. First of the "libs extras" step's installers.
func InstallDocker(ctx context.Context, onLine func(string)) (*runner.Result, error) {
	env := []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin"}
	return runner.Run(ctx, scripts.Combine(scripts.DockerInstall), nil, env, onLine)
}
