package api

import (
	"context"
	"encoding/json"
	"net/http"

	"server-safe/internal/runner"
)

// Event is one line of a newline-delimited JSON stream sent to the browser
// while a module runs. The frontend reads the response body incrementally
// via fetch()'s ReadableStream (no need for a separate job/SSE endpoint).
type Event struct {
	Type   string `json:"type"` // "log" | "result" | "error"
	Line   string `json:"line,omitempty"`
	Result any    `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

func writeEvent(w http.ResponseWriter, flusher http.Flusher, ev Event) {
	b, err := json.Marshal(ev)
	if err != nil {
		return
	}
	w.Write(b)
	w.Write([]byte("\n"))
	flusher.Flush()
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	b, err := json.Marshal(v)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Write(b)
}

// runStreamed is the common handler body shared by every module whose HTTP
// endpoint just streams script log lines and reports a final *runner.Result.
// onDone (optional) runs with the final result before it's written to the
// client — handlers use it to record dashboard progress; it receives res
// even on a script-reported "error" status (e.g. the audit step intentionally
// reports "error" when it finds failed checks, but it still ran).
func runStreamed(w http.ResponseWriter, r *http.Request, run func(ctx context.Context, onLine func(string)) (*runner.Result, error), onDone func(*runner.Result)) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming nao suportado", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/x-ndjson")
	w.WriteHeader(http.StatusOK)

	onLine := func(line string) { writeEvent(w, flusher, Event{Type: "log", Line: line}) }

	res, err := run(r.Context(), onLine)
	if err != nil && res == nil {
		writeEvent(w, flusher, Event{Type: "error", Error: err.Error()})
		return
	}
	if onDone != nil {
		onDone(res)
	}
	writeEvent(w, flusher, Event{Type: "result", Result: res})
}
