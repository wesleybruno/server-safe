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
- `internal/progress`: `Tracker` em memória (nunca em disco) de quais steps já rodaram com sucesso. Reseta a zero se o processo reiniciar; aceitável porque o wizard é pra rodar uma vez só. O checklist do dashboard (`#db-steps`) mostra só os steps "principais" — os 6 `extras_*` (Docker/Portainer/Traefik/Coolify/EasyPanel/cPanel) são filtrados de lá (`app.js` corta prefixo `extras_`) e aparecem como `.status-badge` dentro do próprio item na aba "Libs extras", não duplicados no topo.
- `web/`: HTML/JS vanilla sem build step. Layout é `<nav id="step-nav">` (esquerda) + `<main>` com os `<section class="step">` (direita, um visível por vez via classe `.active`) — `buildStepNav()` em `app.js` gera os botões do menu lendo os `.step` do DOM (id + texto do `<h2>`), **não precisa registrar nada à mão pra step novo**. **Todas as etapas ficam sempre navegáveis e clicáveis desde o início** (sem trava client-side), e **a troca de etapa é sempre iniciada pelo usuário** — `selectStep(sel)` é chamado só de dois lugares: o clique num item do `#step-nav`, e os botões explícitos "continuar" (`btn-continue-timers`/`btn-continue-extras`). O callback de sucesso de uma ação (aplicar SSH, ativar firewall, rodar auditoria, ...) **nunca** chama `selectStep` — só atualiza o próprio painel; a UI não deve pular de etapa sozinha nunca (bug já corrigido uma vez, não reintroduzir). Etapa com dependência real de outra mostra um aviso (`p.warn`) no próprio painel; quem garante de verdade é o backend (ver seção de anti-lockout abaixo), a UI só orienta. O dashboard (`#dashboard` em `index.html`) fica fora desse layout, sempre visível, e se atualiza sozinho via `setInterval(refreshDashboard, 3000)` em `app.js`.
- `web/style.css`: design system em custom properties — paleta clara em `:root`, escura redefinida em `@media (prefers-color-scheme: dark)` (sem toggle manual, segue o SO). Tipografia: IBM Plex Mono (títulos, dados, `.log`) + IBM Plex Sans (corpo/forms), carregadas via Google Fonts no `<head>` do `index.html` — só o browser do admin baixa a fonte, a VM alvo não precisa de internet pra isso. `.log` estilizado como terminal de verdade (`--terminal-bg`/`--terminal-fg`, sempre escuro nos dois temas). **Regra**: `.warn` também é usado como modificador de estado no `.gauge-fill` via JS (`classList.toggle("warn", ...)`) — o estilo de callout (fundo, borda, padding) é `p.warn`, não `.warn` puro, senão vaza pra dentro da barra do gauge.

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
| `POST /api/extras/dozzle` | `InstallDozzle` | `dozzle.go` |
| `POST /api/extras/netdata` | `InstallNetdata` | `netdata.go` |
| `POST /api/extras/restic` | `SetupRestic` | `restic.go` |
| `POST /api/audit/run` | `SecurityAudit` | `audit.go` |
| `POST /api/cleanup/schedule` | `ScheduleCleanup` | `cleanup.go` |
| `GET /api/dashboard` | `Dashboard` | `dashboard.go` |

## Convenção para adicionar um módulo novo

1. Script bash em `internal/scripts/<nome>.sh` (idempotente, usa `result()`/`fail()` de common.sh, env vars prefixadas `SS_`).
2. `//go:embed` var em `internal/scripts/scripts.go`.
3. `internal/modules/<nome>.go`: monta env vars, chama `runner.Run(ctx, scripts.Combine(scripts.X), nil, env, onLine)`.
4. Handler em `internal/api/handlers.go` usando o helper `runStreamed` (a menos que o resultado precise de um shape diferente, como `CreateUser`), passando `h.markOK("<step>")` como `onDone` pra aparecer no dashboard — usa `h.markRan` só se `status: "error"` do script for um resultado válido (achado, não falha), como no `audit`. Step novo precisa entrar em `progress.Steps` também.
5. Rota em `internal/api/router.go`.
6. Step novo em `web/index.html` (sempre acessível, sem `disabled` — se depender de outra etapa, adiciona um `<p class="warn">` explicando) + wiring em `web/app.js`. **Não** chamar `selectStep` no callback de sucesso da ação — troca de etapa é só por clique do usuário (nav ou botão "continuar" explícito).

## Ordem de execução importa (anti-lockout)

Ordem sugerida na UI (nav de cima pra baixo): Users → SSH → Firewall → Fail2ban → Auto-updates → Timers → Extras (libs) → Auditoria → Cleanup. Mas **nenhuma etapa trava a outra na UI** — todo mundo é clicável a qualquer momento. Dependência real (a que de fato pode causar lockout ou erro) é responsabilidade do **script**, não da tela: a UI só mostra um aviso (`.warn`), quem recusa de verdade é o `fail()` do bash na hora de executar. Isso importa pra quem for adicionar um step novo: não dá pra confiar que "se chegou até aqui, a etapa X já rodou" — sempre confira a pré-condição de verdade dentro do próprio script.

"Extras" é uma categoria, não um módulo só: cada lib (Docker, Portainer, Traefik, Coolify, EasyPanel, cPanel, Netdata, Dozzle, Restic) ganha seu próprio par script/módulo/rota/botão dentro do mesmo step `step-extras`, não um framework genérico de "instalar lib X". Roda antes da Auditoria de propósito — instalar software (repos novos, serviços novos escutando) é algo que a auditoria final deve enxergar.

UI da etapa 7: `.extra-card` em grid (`#step-extras .extra-grid`), um card por lib — ícone de marca real (SVG inline, baixado uma vez de `cdn.jsdelivr.net/npm/simple-icons` e colado no `index.html`, **não** carregado do CDN em runtime) ou monograma (`.extra-icon-mono`) quando a marca não tem ícone lá (EasyPanel, Dozzle, Restic — não estão no simple-icons). Sem badge de texto "não instalado" — só um `svg.check-icon` que aparece (`hidden` removido) quando a lib já está instalada, via `app.js`/`setExtraStatuses`/`EXTRA_KEYS` (lista separada do mapa `EXTRAS` de URLs, porque o Restic tem wiring próprio — não é um botão genérico — mas ainda precisa aparecer no check de status).

Nenhuma lib "extra" recusa por dependência faltando — instala junto, sem aviso, e sem exigir que o usuário rode o step do Docker antes (consistente com "nenhuma etapa trava a outra", ver seção de anti-lockout):
- Portainer, Traefik, Netdata e Dozzle rodam via `docker run` direto — se `docker` não estiver no PATH, chamam `ensure_docker` (helper em `common.sh`, extraído de `docker-install.sh` — o mesmo botão "instalar docker" e essas quatro libs chamam a mesma função, sem duplicar a lógica de instalar/habilitar/validar).
- Coolify e EasyPanel rodam os instaladores oficiais dos fornecedores (`curl | bash`/`sh` de `cdn.coollabs.io`/`get.easypanel.io`) — eles mesmos instalam Docker se faltar.
- Como qualquer uma dessas 6 rodar com sucesso garante que o Docker está presente (já estava, ou acabou de ser instalado), o handler Go delas (`h.markOKWithDocker`, `internal/api/handlers.go`) marca `extras_docker` no progress junto com o próprio step — senão o check do card do Docker ficaria incoerente com o estado real da máquina.
- cPanel é o extra mais arriscado do grupo: só funciona em AlmaLinux/CloudLinux/RHEL (o script confere `distro_family` e recusa em Debian/Ubuntu), exige licença paga, demora 1-2h, e assume controle total da máquina (firewall/serviços próprios) — por isso tem aviso (`.warn`) na UI, diferente dos outros extras.

**Mapa de portas loopback dos extras** (`127.0.0.1` só, sempre — ver "Não fazer"): Portainer `9443`, Traefik dashboard `8090` (não `8080` — já é o painel server-safe; já rolou colisão real por isso, cuidado ao adicionar um extra novo, confere contra este mapa antes de escolher porta), Netdata `19999` (porta padrão da própria ferramenta), Dozzle `8081`. Coolify/EasyPanel/cPanel escolhem a própria porta via instalador deles, fora do nosso controle. Restic não tem porta — é só backup agendado (systemd timer), sem UI web.

Restic (`restic-setup.sh`) é o único extra com campos de formulário (`.extra-card-wide` na grid) em vez de um botão só: repositório (aceita qualquer sintaxe do restic — path local, `sftp:`, `s3:`, `b2:` — sem UI dedicada por backend de propósito, evita reinventar config por provedor), paths (validados como absolutos, mesmo padrão do `cleanup-schedule.sh`), agenda. Senha do repo gerada com `random_password` (promovida de `user-create.sh` pra `common.sh` quando o Restic virou o segundo consumidor — **generate_local_password virou random_password**, não duplicar de novo se aparecer um terceiro caso) e salva em `/etc/restic/password` (`600`); mostrada uma vez só (mesmo mecanismo/idioma do `data.password` da etapa 1), nunca sobrescrita se já existir. **Cuidado de quoting**: os comandos de backup/prune vão num script wrapper (`/etc/restic/backup.sh`, `chmod 700`) em vez de direto no `ExecStart=` da unit — `printf '%q'` gera escaping válido pra bash (que roda o wrapper), mas o parser de linha do systemd pra `ExecStart=` é mais simples e não entende a mesma sintaxe; embutir direto quebraria com paths ou repo com espaço/caractere especial.

Etapa 8 (auditoria): sem input de porta na UI — `#au-ssh-port` é um `<input type="hidden">`, ainda preenchido automaticamente pelo callback de sucesso da etapa 2 (SSH), só não aparece mais pro usuário digitar. **Contrato de formato** entre `security-audit.sh` e `app.js`: cada linha do `REPORT` (campo `data.report`) segue `[ok|warn|fail] label - detalhe` — é assim que `renderAuditSummary()` monta o resumo (falhas/alertas) sem precisar reprocessar no Go; mudar esse formato no script quebra o parser regex do frontend (`^\[(ok|warn|fail)\]\s+(\S+)\s+-\s+(.*)$`). A seção do lynis (texto livre, não bate no formato) fica de fora do resumo de propósito, só aparece no `<details>` de relatório completo.

`user-create.sh` gera uma senha local aleatória (`$RANDOM`, 20 chars, sem caracteres ambíguos) e roda `chpasswd` — só pra `sudo`/`su`, não mexe em `PasswordAuthentication` do SSH. Necessário porque a conta não tem senha nenhuma por padrão (só chave) e `sudo` sempre pede uma pra autenticar. Gera sempre que `passwd -S` não reportar status `P` (usável) — cobre usuário novo E usuário que já existia sem senha (ex: criado numa versão anterior desta ferramenta, antes dessa feature existir); nunca sobrescreve senha que já existe de verdade. Vai em `data.password` do `RESULT_JSON` — mesmo mecanismo do `fingerprint`, sem token/download dedicado como a chave privada (não é um arquivo que arrisca ficar em disco, é só pra copiar/colar uma vez).

Cada script deve validar a pré-condição do anterior antes de aplicar algo destrutivo:
- `ssh-harden.sh`, se `SS_DISABLE_PASSWORD=true`, primeiro confere se **existe de fato** uma chave pública em `authorized_keys` de algum usuário sudo/wheel (ou root) — sem isso recusa com `fail()`, porque desativar senha sem chave nenhuma trancaria todo mundo fora. Isso é checagem real do estado do sistema, não o checkbox "já testei a chave" da UI (autodeclarado, só um lembrete visual). Depois roda `sshd -t` antes de restart e confere a porta pelo listener real (`ss -tln`) — não só via `sshd -T`, que em distros com socket activation (Ubuntu 24.04+: `ssh.socket` escuta, `ssh.service` fica "static") não reflete o bind de verdade; nesse caso o script detecta o `.socket` e sobrescreve o `ListenStream` dele em vez de só reiniciar o `.service`. O drop-in vai em `sshd_config.d/00-server-safe.conf` (**não** `99-`) — dentro de `sshd_config.d`, a primeira ocorrência de uma diretiva vence (ao contrário do `jail.d` do fail2ban, que é o oposto); um `99-` perde silenciosamente pra qualquer arquivo anterior que já defina a mesma diretiva (ex: `50-cloud-init.conf` com `PasswordAuthentication` explícito, comum em imagens Ubuntu).
- `firewall-ufw.sh` recusa rodar se o sshd não estiver de fato escutando na porta nova (`ss -tln`) antes de ativar `deny incoming` por padrão.
- `portainer-install.sh`/`traefik-install.sh` recusam com `fail()` se `docker` não estiver no PATH.
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
- Não mapear porta de admin de extra novo sem checar o mapa de portas na seção de anti-lockout primeiro — já rolou colisão real (Traefik dashboard tentando `127.0.0.1:8080`, a mesma porta do próprio painel). Toda porta de admin de extra é `127.0.0.1` (nunca `0.0.0.0`), e precisa ser distinta de todas as outras já em uso.
