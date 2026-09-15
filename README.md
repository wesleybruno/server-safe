# server-safe

Wizard local (web) para configuração inicial de servidores Linux novos: usuário com chave SSH, hardening SSH, firewall, fail2ban, atualizações automáticas, timers de restart, auditoria de segurança e limpeza automática ao final.

## Por quê

Toda máquina Linux nova exige o mesmo checklist manual: trocar porta SSH, desativar login por senha, configurar firewall, fail2ban, etc. O server-safe empacota tudo isso em um binário único com interface web, rodado uma vez por máquina.

## Como funciona

1. Clone este repo na máquina nova.
2. Rode `sudo bash install.sh` — baixa o binário pronto do [último release](https://github.com/wesleybruno/server-safe/releases/latest) (linux/amd64 ou linux/arm64, sem precisar de Go na máquina) e sobe como serviço systemd escutando em `127.0.0.1:8080`. Se ainda não houver release publicado (ou a arquitetura não tiver binário pronto), ele cai pra compilar localmente — nesse caso rode `sudo bash pre-install.sh` antes pra ter o Go instalado.
3. Abra um túnel SSH até o painel (ele só escuta em localhost, de propósito — detalhes e portas extras em [Acesso via túnel SSH](#acesso-via-túnel-ssh)):
   ```
   ssh -L 8080:127.0.0.1:8080 usuario@maquina
   ```
4. Acesse `http://127.0.0.1:8080` no navegador local e siga o wizard. O topo da página tem um dashboard sempre visível com uso de CPU/memória/disco e o checklist de etapas já executadas, atualizado sozinho a cada poucos segundos.
5. No último step, agende a limpeza final — o painel se autodestrói (para o serviço, remove o binário e arquivos temporários).

## Requisitos

- Máquina alvo: Linux com systemd, acesso root.
- Go só é necessário se `install.sh` não achar um binário pronto pra arquitetura da máquina (releases cobrem linux/amd64 e linux/arm64) — nesse caso `pre-install.sh` instala o Go antes.
- Pacotes usados pelos módulos (`ufw`, `fail2ban`, `unattended-upgrades`/`dnf-automatic`, `docker-ce`) precisam estar disponíveis no repositório do sistema — cada módulo instala o que falta automaticamente via `apt-get`/`dnf`/`yum`.

## Passos do wizard

| # | Step | O que faz |
|---|------|-----------|
| 1 | Usuário | Cria usuário sudo novo; gera chave SSH ed25519 ou aceita chave pública importada; gera senha local aleatória (só `sudo`/`su`) |
| 2 | SSH | Muda a porta, desativa login por senha e/ou root |
| 3 | Firewall | Ativa UFW com política deny-default, libera a porta SSH + portas extras |
| 4 | Fail2ban | Jail do sshd configurável (bantime / findtime / maxretry) |
| 5 | Atualizações automáticas | `unattended-upgrades` (Debian/Ubuntu) ou `dnf-automatic` (RHEL/Fedora) |
| 6 | Timers de app | Cria par `.service`/`.timer` do systemd genérico, para restart periódico de qualquer serviço |
| 7 | Libs extras | Instala libs adicionais, uma por botão, organizadas por categoria — Containers (Docker, Portainer, Traefik), Painéis de hospedagem (Coolify, EasyPanel, cPanel/WHM), Logs (Dozzle, Loki), Monitoramento (cAdvisor, Prometheus, Grafana, Uptime Kuma, Zabbix), Backup (Restic — campos próprios de repo/paths/agenda) |
| 8 | Auditoria final | Checa portas expostas pra fora (loopback fica de fora da lista), sudoers com NOPASSWD, contas com UID 0 extra, permissões de `.ssh`, roda `lynis` se disponível |
| 9 | Limpeza | Agenda o self-destruct do painel + remoção de arquivos temporários |

## Acesso via túnel SSH

Painel server-safe e as UIs de admin dos extras só escutam em `127.0.0.1` na máquina — de propósito, nunca expostos direto na internet. Acesso sempre via túnel SSH, um `-L` por porta que você for usar:

```bash
ssh -L 8080:127.0.0.1:8080 \
    -L 9443:127.0.0.1:9443 \
    -L 8090:127.0.0.1:8090 \
    -L 8081:127.0.0.1:8081 \
    -L 8082:127.0.0.1:8082 \
    -L 8083:127.0.0.1:8083 \
    -L 9090:127.0.0.1:9090 \
    -L 3000:127.0.0.1:3000 \
    -L 3100:127.0.0.1:3100 \
    -L 8084:127.0.0.1:8084 \
    usuario@servidor
```

| Porta | Serviço |
|---|---|
| `8080` | painel server-safe → `http://127.0.0.1:8080` |
| `9443` | Portainer (se instalado) → `https://127.0.0.1:9443` |
| `8090` | dashboard Traefik (se instalado) → `http://127.0.0.1:8090` — não é 8080 de propósito, já é o painel |
| `8081` | Dozzle (se instalado) → `http://127.0.0.1:8081` |
| `8082` | Uptime Kuma (se instalado) → `http://127.0.0.1:8082` |
| `8083` | cAdvisor (se instalado) → `http://127.0.0.1:8083` |
| `9090` | Prometheus (se instalado) → `http://127.0.0.1:9090` |
| `3000` | Grafana (se instalado) → `http://127.0.0.1:3000` — login inicial `admin/admin` |
| `3100` | Loki (se instalado) → `http://127.0.0.1:3100` — sem UI própria, é datasource do Grafana |
| `8084` | Zabbix (se instalado) → `http://127.0.0.1:8084` — login inicial `Admin/zabbix` |

Só inclua os `-L` dos serviços que você de fato instalou. Deixe o terminal do SSH aberto enquanto usa. Restic não entra nessa lista — não tem UI web, é só backup agendado (`systemctl list-timers`/`journalctl -u server-safe-restic-backup` pra acompanhar).

cAdvisor, Prometheus, Grafana e Loki (se instalados) ficam todos na mesma rede docker `server-safe-monitoring` — dá pra configurar um datasource do Grafana apontando pra `http://prometheus:9090` ou `http://loki:3100` direto pelo nome do container, sem descobrir IP. Isso não é feito automaticamente (cada extra é independente), é um passo manual dentro da UI de cada ferramenta.

## Segurança da chave SSH gerada

- A chave privada nunca toca disco persistente — fica em `/dev/shm` (RAM/tmpfs).
- O link de download é de uso único e expira em 15 minutos mesmo que ninguém baixe.
- O wizard exige o checkbox "já testei a chave" antes de liberar o step que desativa login por senha, para evitar lockout.

## Senha local do usuário criado

O usuário criado no step 1 não tem senha nenhuma por padrão — login SSH é só por chave. Só que `sudo` sempre pede uma senha pra autenticar, e sem nenhuma cadastrada ele nunca passa. Por isso o wizard gera uma senha local aleatória (20 caracteres, sem `0/O/1/l/I` pra facilitar copiar/ler) e mostra na tela com botão de copiar, uma única vez — não fica salva em arquivo nenhum, não é reexibida depois.

Essa senha só vale pra `sudo`/`su` local — não muda nada no SSH (se o step 2 desativar login por senha, isso continua bloqueado). É defesa extra: mesmo que a chave SSH vaze ou uma sessão seja sequestrada, ainda precisa da senha pra virar root.

Alternativa (não usada aqui de propósito): configurar `NOPASSWD` no sudoers pra não precisar de senha nenhuma. O próprio step 8 (auditoria) do wizard reporta isso como warning (`sudo-nopasswd`), então essa ferramenta não empurra esse caminho por padrão.

## Backup automático (Restic)

O extra Restic (etapa 7) instala o `restic`, inicializa o repositório informado (aceita path local, `sftp:`, `s3:`, `b2:`, qualquer sintaxe que o restic entenda — a UI não tem formulário por provedor, é a mesma string que você usaria no `restic -r`) e agenda backup + `forget --prune` (retenção fixa: 7 diários, 4 semanais, 6 mensais) via `systemd timer`.

A senha do repositório é gerada uma vez (mesma lógica da senha do usuário: 20 caracteres, mostrada uma única vez na UI com botão de copiar) e fica em `/etc/restic/password` (`600`, só root). **Sem essa senha os backups ficam ilegíveis pra sempre** — anote assim que aparecer na tela, não tem como recuperar depois.

## Proteções anti-lockout

- SSH: valida a config (`sshd -t`) antes de reiniciar o serviço, e confere o estado efetivo depois.
- Firewall: só ativa a política deny-default se confirmar que o sshd já está escutando na porta nova.
- Em nenhum step o acesso antigo é fechado antes do novo estar confirmado funcionando.

## Desenvolvimento

```bash
go build ./...
go vet ./...

# binário para distribuir na máquina alvo
GOOS=linux GOARCH=amd64 go build -o server-safe ./cmd/server
```

Rodar localmente só para ver a UI (os módulos exigem root + Linux, então não vão funcionar de fato fora do alvo real):
```bash
go run ./cmd/server --addr 127.0.0.1:8080
```

Pra publicar um release (`.github/workflows/release.yml` builda linux/amd64 + linux/arm64 e anexa como assets `server-safe-linux-<arch>`, é isso que `install.sh` baixa):
```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Status

- Validado: compilação (`go build`/`go vet`), cross-compile (linux/amd64, linux/arm64), sintaxe de todos os scripts bash.
- Não validado: execução real dos módulos (`useradd`, `sshd`, `ufw`, `fail2ban`, `systemd`) em uma máquina Linux de verdade.

**Teste em uma VM ou servidor descartável antes de usar em produção.**
