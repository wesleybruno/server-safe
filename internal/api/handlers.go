package api

import (
	"context"
	"encoding/json"
	"net/http"

	"server-safe/internal/keystore"
	"server-safe/internal/modules"
	"server-safe/internal/runner"
)

type Handlers struct {
	KeyStore *keystore.Store
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
	})
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
	})
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
	})
}

func (h *Handlers) AutoUpdates(w http.ResponseWriter, r *http.Request) {
	var req modules.AutoUpdatesRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.EnableAutoUpdates(ctx, req, onLine)
	})
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
	})
}

func (h *Handlers) SecurityAudit(w http.ResponseWriter, r *http.Request) {
	var req modules.SecurityAuditRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.RunSecurityAudit(ctx, req, onLine)
	})
}

func (h *Handlers) ScheduleCleanup(w http.ResponseWriter, r *http.Request) {
	var req modules.CleanupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "json invalido", http.StatusBadRequest)
		return
	}
	runStreamed(w, r, func(ctx context.Context, onLine func(string)) (*runner.Result, error) {
		return modules.ScheduleCleanup(ctx, req, onLine)
	})
}
