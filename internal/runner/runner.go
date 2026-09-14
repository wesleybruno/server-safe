// Package runner executes embedded bash scripts via stdin and streams their
// output, extracting a final RESULT_JSON: line that scripts emit to report
// structured success/failure back to the caller.
package runner

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"strings"
)

const resultPrefix = "RESULT_JSON:"

// Result is the structured outcome a script reports on its last line.
type Result struct {
	Status string         `json:"status"` // "ok" or "error"
	Detail string         `json:"detail"`
	Data   map[string]any `json:"data,omitempty"`
}

// Run executes script (bash source) with the given args and env, calling
// onLine for every non-result line of combined stdout/stderr as it arrives.
func Run(ctx context.Context, script []byte, args []string, env []string, onLine func(string)) (*Result, error) {
	cmdArgs := append([]string{"-s", "--"}, args...)
	cmd := exec.CommandContext(ctx, "bash", cmdArgs...)
	cmd.Stdin = bytes.NewReader(script)
	cmd.Env = env

	pr, pw := io.Pipe()
	cmd.Stdout = pw
	cmd.Stderr = pw

	if err := cmd.Start(); err != nil {
		pw.Close()
		return nil, fmt.Errorf("start script: %w", err)
	}

	waitDone := make(chan error, 1)
	go func() {
		waitDone <- cmd.Wait()
		pw.Close()
	}()

	var result *Result
	scanner := bufio.NewScanner(pr)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if payload, ok := strings.CutPrefix(line, resultPrefix); ok {
			var r Result
			if err := json.Unmarshal([]byte(payload), &r); err == nil {
				result = &r
				continue
			}
		}
		if onLine != nil {
			onLine(line)
		}
	}

	waitErr := <-waitDone

	if result == nil {
		status := "ok"
		detail := "script nao emitiu RESULT_JSON"
		if waitErr != nil {
			status = "error"
			detail = waitErr.Error()
		}
		result = &Result{Status: status, Detail: detail}
	} else if waitErr != nil && result.Status == "ok" {
		result.Status = "error"
		if result.Detail == "" {
			result.Detail = waitErr.Error()
		}
	}

	return result, waitErr
}
