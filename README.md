# server-safe

Wizard local (web) para configuração inicial de servidores Linux novos: usuário com chave SSH, hardening SSH, firewall, fail2ban, atualizações automáticas, timers de restart, auditoria de segurança e limpeza automática ao final.

## Por quê

Toda máquina Linux nova exige o mesmo checklist manual: trocar porta SSH, desativar login por senha, configurar firewall, fail2ban, etc. O server-safe empacota tudo isso em um binário único com interface web, rodado uma vez por máquina.

## Como funciona

1. Clone este repo na máquina nova.
2. Máquina sem Go instalado? Rode `sudo bash pre-install.sh` primeiro — atualiza os pacotes do sistema e instala o Go.
3. Rode `sudo bash install.sh` — compila localmente com Go e sobe como serviço systemd escutando em `127.0.0.1:8080`.
4. Abra um túnel SSH até o painel (ele só escuta em localhost, de propósito):
   ```
   ssh -L 8080:127.0.0.1:8080 usuario@maquina
   ```
5. Acesse `http://127.0.0.1:8080` no navegador local e siga o wizard. O topo da página tem um dashboard sempre visível com uso de CPU/memória/disco e o checklist de etapas já executadas, atualizado sozinho a cada poucos segundos.
6. No último step, agende a limpeza final — o painel se autodestrói (para o serviço, remove o binário e arquivos temporários).

## Requisitos

- Máquina alvo: Linux com systemd, acesso root.
- Go instalado na máquina alvo para compilar (`install.sh` builda a partir do repo) — `pre-install.sh` resolve isso se faltar. Distribuição via binário pré-compilado ainda não existe — ver TODO em `install.sh`.
- Pacotes usados pelos módulos (`ufw`, `fail2ban`, `unattended-upgrades`/`dnf-automatic`, `docker-ce`) precisam estar disponíveis no repositório do sistema — cada módulo instala o que falta automaticamente via `apt-get`/`dnf`/`yum`.

## Passos do wizard

| # | Step | O que faz |
|---|------|-----------|
| 1 | Usuário | Cria usuário sudo novo; gera chave SSH ed25519 ou aceita chave pública importada |
| 2 | SSH | Muda a porta, desativa login por senha e/ou root |
| 3 | Firewall | Ativa UFW com política deny-default, libera a porta SSH + portas extras |
| 4 | Fail2ban | Jail do sshd configurável (bantime / findtime / maxretry) |
| 5 | Atualizações automáticas | `unattended-upgrades` (Debian/Ubuntu) ou `dnf-automatic` (RHEL/Fedora) |
| 6 | Timers de app | Cria par `.service`/`.timer` do systemd genérico, para restart periódico de qualquer serviço |
| 7 | Libs extras | Instala libs adicionais, uma por botão: Docker, Portainer, Traefik, Coolify, EasyPanel, cPanel/WHM |
| 8 | Auditoria final | Checa portas abertas, sudoers com NOPASSWD, contas com UID 0 extra, permissões de `.ssh`, roda `lynis` se disponível |
| 9 | Limpeza | Agenda o self-destruct do painel + remoção de arquivos temporários |

## Segurança da chave SSH gerada

- A chave privada nunca toca disco persistente — fica em `/dev/shm` (RAM/tmpfs).
- O link de download é de uso único e expira em 15 minutos mesmo que ninguém baixe.
- O wizard exige o checkbox "já testei a chave" antes de liberar o step que desativa login por senha, para evitar lockout.

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

## Status

- Validado: compilação (`go build`/`go vet`), cross-compile (linux/amd64, linux/arm64), sintaxe de todos os scripts bash.
- Não validado: execução real dos módulos (`useradd`, `sshd`, `ufw`, `fail2ban`, `systemd`) em uma máquina Linux de verdade.

**Teste em uma VM ou servidor descartável antes de usar em produção.**
