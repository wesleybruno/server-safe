package api

import (
	"context"
	"encoding/json"
	"net/http"

	"server-safe/internal/keystore"
	"server-safe/internal/modules"
	"server-safe/internal/progress"
	"server-safe/internal/runner"
)

type Handlers struct {
	KeyStore *keystore.Store
	Progress *progress.Tracker
	Version  string
}

// markOK returns a runStreamed onDone callback that records step as done
// only when the script itself reports success — right for every step that
// mutates the system (a failed run means nothing actually changed).
func (h *Handlers) markOK(step string) func(*runner.Result) {
	return func(res *runner.Result) {
		if res != nil && res.Status == "ok" {
			h.Progress.Mark(step)
		}
	}
}

// markRan records step as done as soon as the script completes, regardless
// of status — for read-only steps (the audit) whose "error" status reports
// findings, not a failed run.
func (h *Handlers) markRan(step string) func(*runner.Result) {
	return func(res *runner.Result) {
		if res != nil {
			h.Progress.Mark(step)
		}
	}
}

// markOKWithDocker is markOK plus "extras_docker" — for extras that
// silently install Docker as a dependency of their own success (Portainer,
// Traefik via ensure_docker in common.sh; Coolify, EasyPanel via their own
// vendor installer). If the step succeeded, Docker is guaranteed present
// either way, so the dashboard/card should reflect that too.
func (h *Handlers) markOKWithDocker(step string) func(*runner.Result) {
	return func(res *runner.Result) {
		if res != nil && res.Status == "ok" {
			h.Progress.Mark(step)
			h.Progress.Mark("extras_docker")
		}
	}
}

func (h *Handlers) CreateUser(w http.ResponseWriter, r *http.Request) {
	var req modules.CreateUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	if req.Username == "" {
		http.Error(w, "username obrigatorio", http.StatusBadRequest)
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming nao suportado", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/x-ndjson")
	w.WriteHeader(http.StatusOK)

	onLine := func(line string) { writeEvent(w, flusher, Event{Type: "log", Line: line}) }

	outcome, err := modules.CreateUser(r.Context(), h.KeyStore, req, onLine)
	if err != nil {
		writeEvent(w, flusher, Event{Type: "error", Error: err.Error()})
		return
	}
	if outcome.Result != nil && outcome.Result.Status == "ok" {
		h.Progress.Mark("users")
	}
	writeEvent(w, flusher, Event{Type: "result", Result: outcome})
}

func (h *Handlers) DownloadKey(w http.ResponseWriter, r *http.Request) {
	token := r.PathValue("token")
	path, ok := h.KeyStore.KeyPath(token)
	if !ok {
		http.Error(w, "chave nao encontrada, ja baixada ou expirada", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Disposition", "attachment; filename=id_ed25519")
	w.Header().Set("Content-Type", "application/octet-stream")
	http.ServeFile(w, r, path)
	h.KeyStore.MarkDownloaded(token)
}

func (h *Handlers) HardenSSH(w http.ResponseWriter, r *http.Request) {
	var req modules.HardenSSHRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	if req.Port <= 0 {
		http.Error(w, "port obrigatorio", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.HardenSSH(ctx, req, onLine)
	}, h.markOK("ssh"))
}

func (h *Handlers) Firewall(w http.ResponseWriter, r *http.Request) {
	var req modules.FirewallRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	if req.SSHPort <= 0 {
		http.Error(w, "ssh_port obrigatorio", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.EnableFirewall(ctx, req, onLine)
	}, h.markOK("firewall"))
}

func (h *Handlers) Fail2ban(w http.ResponseWriter, r *http.Request) {
	var req modules.Fail2banRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	if req.SSHPort <= 0 {
		http.Error(w, "ssh_port obrigatorio", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.EnableFail2ban(ctx, req, onLine)
	}, h.markOK("fail2ban"))
}

func (h *Handlers) AutoUpdates(w http.ResponseWriter, r *http.Request) {
	var req modules.AutoUpdatesRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.EnableAutoUpdates(ctx, req, onLine)
	}, h.markOK("updates"))
}

func (h *Handlers) CreateAppTimer(w http.ResponseWriter, r *http.Request) {
	var req modules.AppTimerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	if req.Name == "" || req.Command == "" || req.OnCalendar == "" {
		http.Error(w, "name, command e on_calendar sao obrigatorios", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.CreateAppTimer(ctx, req, onLine)
	}, h.markOK("timers"))
}

func (h *Handlers) InstallDocker(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallDocker(ctx, onLine)
	}, h.markOK("extras_docker"))
}

func (h *Handlers) InstallPortainer(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallPortainer(ctx, onLine)
	}, h.markOKWithDocker("extras_portainer"))
}

func (h *Handlers) InstallTraefik(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallTraefik(ctx, onLine)
	}, h.markOKWithDocker("extras_traefik"))
}

func (h *Handlers) InstallCoolify(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallCoolify(ctx, onLine)
	}, h.markOKWithDocker("extras_coolify"))
}

func (h *Handlers) InstallEasyPanel(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallEasyPanel(ctx, onLine)
	}, h.markOKWithDocker("extras_easypanel"))
}

func (h *Handlers) InstallCPanel(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallCPanel(ctx, onLine)
	}, h.markOK("extras_cpanel"))
}

func (h *Handlers) InstallDozzle(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallDozzle(ctx, onLine)
	}, h.markOKWithDocker("extras_dozzle"))
}

func (h *Handlers) SetupRestic(w http.ResponseWriter, r *http.Request) {
	var req modules.ResticRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	if req.Repo == "" || req.Paths == "" {
		http.Error(w, "repo e paths sao obrigatorios", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.SetupRestic(ctx, req, onLine)
	}, h.markOK("extras_restic"))
}

func (h *Handlers) InstallUptimeKuma(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallUptimeKuma(ctx, onLine)
	}, h.markOKWithDocker("extras_uptimekuma"))
}

func (h *Handlers) InstallCadvisor(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallCadvisor(ctx, onLine)
	}, h.markOKWithDocker("extras_cadvisor"))
}

func (h *Handlers) InstallPrometheus(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallPrometheus(ctx, onLine)
	}, h.markOKWithDocker("extras_prometheus"))
}

func (h *Handlers) InstallGrafana(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallGrafana(ctx, onLine)
	}, h.markOKWithDocker("extras_grafana"))
}

func (h *Handlers) InstallLoki(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallLoki(ctx, onLine)
	}, h.markOKWithDocker("extras_loki"))
}

func (h *Handlers) InstallZabbix(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallZabbix(ctx, onLine)
	}, h.markOKWithDocker("extras_zabbix"))
}

func (h *Handlers) InstallSignoz(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallSignoz(ctx, onLine)
	}, h.markOKWithDocker("extras_signoz"))
}

func (h *Handlers) InstallNetdata(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallNetdata(ctx, onLine)
	}, h.markOKWithDocker("extras_netdata"))
}

func (h *Handlers) InstallNodeExporter(w http.ResponseWriter, r *http.Request) {
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.InstallNodeExporter(ctx, onLine)
	}, h.markOKWithDocker("extras_nodeexporter"))
}

func (h *Handlers) SecurityAudit(w http.ResponseWriter, r *http.Request) {
	var req modules.SecurityAuditRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.RunSecurityAudit(ctx, req, onLine)
	}, h.markRan("audit"))
}

func (h *Handlers) ScheduleCleanup(w http.ResponseWriter, r *http.Request) {
	var req modules.CleanupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.ScheduleCleanup(ctx, req, onLine)
	}, h.markOK("cleanup"))
}

// Dashboard reports live CPU/memory/disk usage plus which wizard steps have
// run — unlike every other endpoint this is a plain JSON GET (no log lines
// to stream), meant to be polled.
func (h *Handlers) Dashboard(w http.ResponseWriter, r *http.Request) {
	res, err := modules.ReadDashboardStats(r.Context())
	var stats map[string]any
	if err == nil && res != nil && res.Status == "ok" {
		stats = res.Data
	}
	if stats == nil {
		stats = map[string]any{}
	}
	writeJSON(w, map[string]any{
		"stats":       stats,
		"steps":       h.Progress.Snapshot(),
		"steps_order": progress.Steps,
		"version":     h.Version,
	})
}
