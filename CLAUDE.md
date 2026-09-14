# server-safe

Wizard web local para hardening inicial de servidor Linux novo. Binário Go único, scripts bash embutidos, frontend embutido.

## Arquitetura

- `pre-install.sh` / `install.sh` (raiz do repo): bootstrap standalone, rodado direto pelo admin (`sudo bash <script>`) — não passam por `runner`/`common.sh`/`RESULT_JSON`, esse contrato é só para os módulos do wizard. `pre-install.sh` atualiza o sistema e instala Go; `install.sh` baixa o binário pronto do último GitHub Release (`server-safe-linux-<amd64|arm64>`) e só compila localmente (exigindo Go) se não achar release pra arquitetura.
- `.github/workflows/release.yml`: builda linux/amd64 + linux/arm64 (`CGO_ENABLED=0`) e publica como release ao dar push numa tag `v*.*.*` — é isso que `install.sh` baixa. Builda com `-ldflags "-X main.version=${{ github.ref_name }}"`, é assim que a tag chega no binário.
- `cmd/server/main.go`: entrypoint, flags `--addr`/`--keydir`/`--key-ttl`. `var version = "dev"` só muda via `-X main.version=...` no build (release); `go build`/`go run` local sem ldflags fica "dev" mesmo. Versão vai em `Handlers.Version` → `GET /api/dashboard` → `app.js` seta `document.title` a cada poll, pra sempre dar pra ver na aba do navegador se o binário rodando é o esperado. O mux serve `web.Files` (`embed.FS`) atrás de um middleware `noCache` — `embed.FS` reporta `ModTime` zero pra todo arquivo, então sem isso o browser não tem sinal nenhum de que o conteúdo mudou entre versões e pode ficar servindo `app.js`/`index.html` velhos do cache mesmo depois de atualizar o binário.
- `internal/runner`: executa bash via stdin (`bash -s -- args`), sem gravar scripts em disco. O script deve emitir uma última linha `RESULT_JSON:{"status":"ok|error","detail":"...","data":{...}}` — esse é o contrato entre bash e Go.
- `internal/scripts/common.sh`: helpers compartilhados (`result()`, `fail()`, `ensure_installed()`, `distro_family()`, `json_escape()`). Todo módulo é concatenado com `common.sh` via `scripts.Combine()` antes de rodar — **não duplicar essas funções em scripts novos**. **Nunca escreva `"${var:-{}}"`** (ou qualquer default de parâmetro cujo valor literal comece com `{`) — o bash fecha o `${...}` no primeiro `}` que encontra dentro do valor-padrão, sobra um `}` solto grudado no fim, e quebra o JSON de qualquer chamada que passe dado de verdade (não só quando o default entra em jogo). `result()` usa `if [[ -z "$data" ]]; then data="{}"; fi` por causa disso — foi bug real, quebrou silenciosamente o campo `data` de todo `RESULT_JSON` do projeto por um bom tempo (o Go cai no fallback genérico "script nao emitiu RESULT_JSON" quando o JSON não parseia, sem erro óbvio na hora).
- `internal/keystore`: chaves SSH privadas geradas ficam em tmpfs (`/dev/shm`), nunca em disco persistente. Token de download único, TTL, shred após uso ou expiração.
- `internal/api`: endpoints fazem streaming NDJSON (não SSE) — permite POST com body e streaming de log ao mesmo tempo. Frontend consome via `fetch()` + `ReadableStream`. Exceção: `GET /api/dashboard` é JSON simples (sem log pra streamar), feito pra ser pollado.
- `internal/progress`: `Tracker` em memória (nunca em disco) de quais steps já rodaram com sucesso — é o que o dashboard mostra no checklist. Reseta a zero se o processo reiniciar; aceitável porque o wizard é pra rodar uma vez só.
- `web/`: HTML/JS vanilla sem build step. Wizard sequencial: cada step só desbloqueia o próximo após receber `status: "ok"`. Layout é `<nav id="step-nav">` (esquerda) + `<main>` com os `<section class="step">` (direita, um visível por vez via classe `.active`) — `buildStepNav()` em `app.js` gera os botões do menu lendo os `.step` do DOM (id + texto do `<h2>`), **não precisa registrar nada à mão pra step novo**. `unlock(stepSel, btnSel)` continua sendo o único jeito de destravar um step — agora também destrava o botão do menu e navega até ele. Step ainda com classe `.disabled` = item do menu com `disabled` no `<button>`, não dá pra clicar. O dashboard (`#dashboard` em `index.html`) é a exceção — fica fora desse layout, sempre visível, sem gate de step anterior, e se atualiza sozinho via `setInterval(refreshDashboard, 3000)` em `app.js`.

## Rotas (`internal/api/router.go`)

| Rota | Handler | Módulo |
|------|---------|--------|
| `POST /api/users/create` | `CreateUser` | `users.go` |
| `GET /download/key/{token}` | `DownloadKey` | `keystore` |
| `POST /api/ssh/harden` | `HardenSSH` | `ssh.go` |
| `POST /api/firewall/enable` | `Firewall` | `firewall.go` |
| `POST /api/fail2ban/enable` | `Fail2ban` | `fail2ban.go` |
| `POST /api/updates/enable` | `AutoUpdates` | `updates.go` |
| `POST /api/timers/create` | `CreateAppTimer` | `timer.go` |
| `POST /api/extras/docker` | `InstallDocker` | `docker.go` |
| `POST /api/extras/portainer` | `InstallPortainer` | `portainer.go` |
| `POST /api/extras/traefik` | `InstallTraefik` | `traefik.go` |
| `POST /api/extras/coolify` | `InstallCoolify` | `coolify.go` |
| `POST /api/extras/easypanel` | `InstallEasyPanel` | `easypanel.go` |
| `POST /api/extras/cpanel` | `InstallCPanel` | `cpanel.go` |
| `POST /api/audit/run` | `SecurityAudit` | `audit.go` |
| `POST /api/cleanup/schedule` | `ScheduleCleanup` | `cleanup.go` |
| `GET /api/dashboard` | `Dashboard` | `dashboard.go` |

## Convenção para adicionar um módulo novo

1. Script bash em `internal/scripts/<nome>.sh` (idempotente, usa `result()`/`fail()` de common.sh, env vars prefixadas `SS_`).
2. `//go:embed` var em `internal/scripts/scripts.go`.
3. `internal/modules/<nome>.go`: monta env vars, chama `runner.Run(ctx, scripts.Combine(scripts.X), nil, env, onLine)`.
4. Handler em `internal/api/handlers.go` usando o helper `runStreamed` (a menos que o resultado precise de um shape diferente, como `CreateUser`), passando `h.markOK("<step>")` como `onDone` pra aparecer no dashboard — usa `h.markRan` só se `status: "error"` do script for um resultado válido (achado, não falha), como no `audit`. Step novo precisa entrar em `progress.Steps` também.
5. Rota em `internal/api/router.go`.
6. Step novo em `web/index.html` + wiring em `web/app.js` (desbloqueia via `unlock(sel, btnSel)` no callback de sucesso do step anterior).

## Ordem de execução importa (anti-lockout)

Users → SSH → Firewall → Fail2ban → Auto-updates → Timers → Extras (libs) → Auditoria → Cleanup.

"Extras" é uma categoria, não um módulo só: cada lib (Docker, Portainer, Traefik, Coolify, EasyPanel, cPanel) ganha seu próprio par script/módulo/rota/botão dentro do mesmo step `step-extras`, não um framework genérico de "instalar lib X". Roda antes da Auditoria de propósito — instalar software (repos novos, serviços novos escutando) é algo que a auditoria final deve enxergar.

Dentro de "extras":
- Portainer e Traefik rodam via `docker run` direto — dependem do Docker já instalado (o script falha com `fail()` se `docker` não existir no PATH). UI de administração (Portainer 9443, dashboard do Traefik 8080) amarrada em `127.0.0.1` — mesma postura do próprio painel server-safe, acesso só via túnel SSH; portas de dado do Traefik (80/443) ficam públicas porque é o trabalho dele.
- Coolify e EasyPanel rodam os instaladores oficiais dos fornecedores (`curl | bash`/`sh` de `cdn.coollabs.io`/`get.easypanel.io`) — eles mesmos instalam Docker se faltar, não dependem do step Docker daqui.
- cPanel é o extra mais arriscado do grupo: só funciona em AlmaLinux/CloudLinux/RHEL (o script confere `distro_family` e recusa em Debian/Ubuntu), exige licença paga, demora 1-2h, e assume controle total da máquina (firewall/serviços próprios) — por isso tem aviso (`.warn`) na UI, diferente dos outros extras.

`user-create.sh` gera uma senha local aleatória (`$RANDOM`, 20 chars, sem caracteres ambíguos) e roda `chpasswd` — só pra `sudo`/`su`, não mexe em `PasswordAuthentication` do SSH. Necessário porque a conta não tem senha nenhuma por padrão (só chave) e `sudo` sempre pede uma pra autenticar. Gera sempre que `passwd -S` não reportar status `P` (usável) — cobre usuário novo E usuário que já existia sem senha (ex: criado numa versão anterior desta ferramenta, antes dessa feature existir); nunca sobrescreve senha que já existe de verdade. Vai em `data.password` do `RESULT_JSON` — mesmo mecanismo do `fingerprint`, sem token/download dedicado como a chave privada (não é um arquivo que arrisca ficar em disco, é só pra copiar/colar uma vez).

Cada script deve validar a pré-condição do anterior antes de aplicar algo destrutivo:
- `ssh-harden.sh` roda `sshd -t` antes de restart e confere a porta pelo listener real (`ss -tln`) depois — não só via `sshd -T`, que em distros com socket activation (Ubuntu 24.04+: `ssh.socket` escuta, `ssh.service` fica "static") não reflete o bind de verdade. Nesse caso o script detecta o `.socket` e sobrescreve o `ListenStream` dele em vez de só reiniciar o `.service`. O drop-in vai em `sshd_config.d/00-server-safe.conf` (**não** `99-`) — dentro de `sshd_config.d`, a primeira ocorrência de uma diretiva vence (ao contrário do `jail.d` do fail2ban, que é o oposto); um `99-` perde silenciosamente pra qualquer arquivo anterior que já defina a mesma diretiva (ex: `50-cloud-init.conf` com `PasswordAuthentication` explícito, comum em imagens Ubuntu).
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

# ver a UI localmente (sem root/Linux os módulos vão falhar, mas dá pra navegar o wizard)
go run ./cmd/server --addr 127.0.0.1:8080
```

Sem ambiente Linux neste repo para rodar os módulos de fato (useradd/systemctl/ufw/fail2ban) — só validação estática (compilação + sintaxe). **Testar em VM/servidor descartável antes de qualquer uso real.** Não há testes Go automatizados no repo (`*_test.go`) — validação é build/vet/gofmt + `bash -n`.

## Não fazer

- Não duplicar `result()`/`fail()`/helpers dentro de um script de módulo — vêm de `common.sh` via `Combine()`.
- Não usar `sed -i` genérico em arquivos de configuração de sistema (sshd_config) — usar drop-ins (`/etc/ssh/sshd_config.d/`, `/etc/fail2ban/jail.d/`).
- Não persistir chave privada SSH fora de `/dev/shm`.
- Não commitar binários compilados (`.gitignore` já cobre `/server-safe`, `/server-safe.exe`, `/bin/`).
