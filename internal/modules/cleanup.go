package modules

import (
	"context"
	"fmt"
	"strings"

	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type CleanupRequest struct {
	Delay          string   `json:"delay,omitempty"`         // ex: "5min", default "5min"
	Paths          []string `json:"paths,omitempty"`         // absolute paths to remove (e.g. leftover installer)
	SelfDestruct   *bool    `json:"self_destruct,omitempty"` // default true
	StopContainers bool     `json:"stop_containers,omitempty"`
	RemoveImages   bool     `json:"remove_images,omitempty"` // implies stopping+removing all containers too (Docker won't drop an image a container still references)
}

// ScheduleCleanup schedules, a short delay after this call returns (so the
// HTTP response reaches the browser first), the removal of leftover install
// files and — unless SelfDestruct is explicitly false — the server-safe
// service itself (stopped, disabled, unit file removed).
func ScheduleCleanup(ctx context.Context, req CleanupRequest, onLine func(string)) (*runner.Result, error) {
	delay := req.Delay
	if delay == "" {
		delay = "5min"
	}
	selfDestruct := true
	if req.SelfDestruct != nil {
		selfDestruct = *req.SelfDestruct
	}
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		"SS_DELAY=" + delay,
		"SS_PATHS=" + strings.Join(req.Paths, ","),
		fmt.Sprintf("SS_SELF_DESTRUCT=%t", selfDestruct),
		fmt.Sprintf("SS_STOP_CONTAINERS=%t", req.StopContainers),
		fmt.Sprintf("SS_REMOVE_IMAGES=%t", req.RemoveImages),
	}
	return runner.Run(ctx, scripts.Combine(scripts.CleanupSchedule), nil, env, onLine)
}
