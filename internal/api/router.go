package api

import (
	"net/http"

	"server-safe/internal/keystore"
)

// RegisterRoutes adds server-safe's API endpoints onto an existing mux, so
// the caller can also mount the static web UI at "/" on the same mux.
func RegisterRoutes(mux *http.ServeMux, ks *keystore.Store) {
	h := &Handlers{KeyStore: ks}
	mux.HandleFunc("POST /api/users/create", h.CreateUser)
	mux.HandleFunc("GET /download/key/{token}", h.DownloadKey)
	mux.HandleFunc("POST /api/ssh/harden", h.HardenSSH)
	mux.HandleFunc("POST /api/firewall/enable", h.Firewall)
	mux.HandleFunc("POST /api/fail2ban/enable", h.Fail2ban)
	mux.HandleFunc("POST /api/updates/enable", h.AutoUpdates)
	mux.HandleFunc("POST /api/timers/create", h.CreateAppTimer)
	mux.HandleFunc("POST /api/audit/run", h.SecurityAudit)
	mux.HandleFunc("POST /api/cleanup/schedule", h.ScheduleCleanup)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
}
