# server-safe

Wizard web local para hardening inicial de servidor Linux novo. Binário Go único, scripts bash embutidos, frontend embutido.

## Arquitetura

- `cmd/server/main.go`: entrypoint, flags `--addr`/`--keydir`/`--key-ttl`.
- `internal/runner`: executa bash via stdin (`bash -s -- args`), sem gravar scripts em disco. O script deve emitir uma última linha `RESULT_JSON:{"status":"ok|error","detail":"...","data":{...}}` — esse é o contrato entre bash e Go.
- `internal/scripts/common.sh`: helpers compartilhados (`result()`, `fail()`, `ensure_installed()`, `distro_family()`, `json_escape()`). Todo módulo é concatenado com `common.sh` via `scripts.Combine()` antes de rodar — **não duplicar essas funções em scripts novos**.
- `internal/keystore`: chaves SSH privadas geradas ficam em tmpfs (`/dev/shm`), nunca em disco persistente. Token de download único, TTL, shred após uso ou expiração.
- `internal/api`: endpoints fazem streaming NDJSON (não SSE) — permite POST com body e streaming de log ao mesmo tempo. Frontend consome via `fetch()` + `ReadableStream`.
- `web/`: HTML/JS vanilla sem build step. Wizard sequencial: cada step só desbloqueia o próximo após receber `status: "ok"`.

## Convenção para adicionar um módulo novo

1. Script bash em `internal/scripts/<nome>.sh` (idempotente, usa `result()`/`fail()` de common.sh, env vars prefixadas `SS_`).
2. `//go:embed` var em `internal/scripts/scripts.go`.
3. `internal/modules/<nome>.go`: monta env vars, chama `runner.Run(ctx, scripts.Combine(scripts.X), nil, env, onLine)`.
4. Handler em `internal/api/handlers.go` usando o helper `runStreamed` (a menos que o resultado precise de um shape diferente, como `CreateUser`).
5. Rota em `internal/api/router.go`.
6. Step novo em `web/index.html` + wiring em `web/app.js` (desbloqueia via `unlock(sel, btnSel)` no callback de sucesso do step anterior).

## Ordem de execução importa (anti-lockout)

Users → SSH → Firewall → Fail2ban → Auto-updates → Timers → Auditoria → Cleanup.

Cada script deve validar a pré-condição do anterior antes de aplicar algo destrutivo:
- `ssh-harden.sh` roda `sshd -t` antes de restart e confere estado efetivo (`sshd -T`) depois.
- `firewall-ufw.sh` recusa rodar se o sshd não estiver de fato escutando na porta nova (`ss -tln`) antes de ativar `deny incoming` por padrão.
- Nunca fechar acesso antigo antes do novo estar confirmado.

## Build / validação

```bash
go build ./...
go vet ./...
gofmt -l .                      # deve ficar vazio

# scripts bash não rodam sozinhos (dependem de common.sh) — check real:
cat internal/scripts/common.sh internal/scripts/<nome>.sh > /tmp/x.sh && bash -n /tmp/x.sh

GOOS=linux GOARCH=amd64 go build -o /tmp/server-safe ./cmd/server   # binário real de distribuição
```

Sem ambiente Linux neste repo para rodar os módulos de fato (useradd/systemctl/ufw/fail2ban) — só validação estática (compilação + sintaxe). **Testar em VM/servidor descartável antes de qualquer uso real.**

## Não fazer

- Não duplicar `result()`/`fail()`/helpers dentro de um script de módulo — vêm de `common.sh` via `Combine()`.
- Não usar `sed -i` genérico em arquivos de configuração de sistema (sshd_config) — usar drop-ins (`/etc/ssh/sshd_config.d/`, `/etc/fail2ban/jail.d/`).
- Não persistir chave privada SSH fora de `/dev/shm`.
- Não commitar binários compilados (`.gitignore` já cobre `/server-safe`, `/server-safe.exe`, `/bin/`).
