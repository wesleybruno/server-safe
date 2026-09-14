// Package progress tracks, in memory only, which wizard steps have already
// run successfully. Nothing here touches disk — same as the rest of
// server-safe, this state is gone the moment the process restarts, which is
// fine since the wizard is meant to run once per machine.
package progress

import "sync"

// Steps lists every wizard step in wizard order, so the dashboard can
// render them in order regardless of map iteration.
var Steps = []string{
	"users",
	"ssh",
	"firewall",
	"fail2ban",
	"updates",
	"timers",
	"extras_docker",
	"extras_portainer",
	"extras_traefik",
	"extras_coolify",
	"extras_easypanel",
	"extras_cpanel",
	"extras_dozzle",
	"extras_netdata",
	"extras_restic",
	"audit",
	"cleanup",
}

// Tracker records which steps have run. Zero value is not usable, use New.
type Tracker struct {
	mu   sync.Mutex
	done map[string]bool
}

func New() *Tracker {
	return &Tracker{done: make(map[string]bool)}
}

// Mark records step as having run. Unknown step names are recorded too
// (harmless — Snapshot only reads back the names in Steps).
func (t *Tracker) Mark(step string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.done[step] = true
}

// Snapshot returns done-state for every known step.
func (t *Tracker) Snapshot() map[string]bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	out := make(map[string]bool, len(Steps))
	for _, s := range Steps {
		out[s] = t.done[s]
	}
	return out
}
