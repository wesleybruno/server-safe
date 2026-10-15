# ansible/

Playbooks pra configurar uma VPS já hardenizada pelo wizard server-safe,
rodados **da máquina do admin** (não do binário Go, não da própria VPS).
Complementa o wizard, não substitui: o server-safe cuida do hardening
inicial (users/SSH/firewall/fail2ban/updates) de forma zero-dependency
(binário único, sem exigir nada instalado na VPS além de bash); estes
playbooks cuidam da configuração de infra recorrente (Docker Swarm,
Traefik, Portainer, e o que vier depois) e exigem Ansible + Python na sua
máquina de controle (a VPS só precisa do Python que o Ansible já exige de
qualquer managed node) — **precisa rodar de um controle Linux/WSL/macOS**,
Ansible não roda nativamente no Windows.

## Arquitetura: swarm + traefik como único ponto de entrada

- `docker` inicializa modo swarm (manager único, sem join de workers por
  ora) — necessário pra `docker service create`.
- `traefik` sobe como **service** do swarm, na rede overlay
  `server-safe-proxy` (`--attachable`). **É a única porta publicada do
  stack inteiro** (80/443, `mode=host`) — de propósito, é o roteador.
- `portainer` sobe como service **sem publicar porta nenhuma** — só é
  alcançável através do traefik, via label (`Host()` + rede overlay).

Por que não publicar 9443/8090 direto como antes (bash/`docker run`):
**Docker Swarm `--publish` não suporta bind em IP específico** (sempre
`0.0.0.0`, mesmo em `mode=host`) — diferente do `docker run -p
127.0.0.1:PORT:PORT`. E o `ufw` do wizard (`firewall-ufw.sh`) não filtra
isso: Docker escreve regras de `iptables` direto e **contorna o ufw** pra
portas publicadas por container/service. Publicar essas portas em modo
swarm exporia de verdade na internet. Por isso a mudança de modelo: em vez
de "porta loopback + túnel SSH", agora é "porta pública só do traefik +
roteamento por domínio":
  - **Dashboard do traefik**: roteado via `Host({{ traefik_dashboard_host
    }})` + middleware `basicauth` (usuário/senha gerados na primeira
    execução, mostrados uma vez só no output do Ansible — não reexibidos).
  - **Portainer**: roteado via `Host({{ portainer_host }})`, autenticação
    é o próprio login do Portainer (não precisa de basicauth extra).

TLS via Let's Encrypt (`certificatesresolvers.letsencrypt`, challenge
`http-01` na porta 80, redirect automático `http`→`https`) já está
configurado — **mas este é um template white-label**: `traefik_dashboard_host`,
`portainer_host` e `traefik_acme_email` nos `defaults/main.yml` são
placeholders fictícios (`*.example.com`, `admin@example.com`) e
`traefik_acme_ca_server` aponta pro ambiente **staging** do Let's Encrypt
(certificados não confiáveis pelo browser, mas sem risco de rate-limit —
seguro pra rodar o template repetidas vezes durante testes). Nada disso
emite certificado de verdade até você substituir pelos valores reais do
cliente/deploy — ver `group_vars/vps.yml.example` (seção Setup abaixo).

## Pré-requisitos

- Ansible instalado na sua máquina de controle (`pip install ansible`).
- VPS já passou pelas etapas **Users** e **SSH** do wizard server-safe —
  precisamos do usuário sudo + chave privada que ele gerou.
- Pra TLS de verdade (fora do staging): domínio(s) com DNS já apontando
  pro IP público da VPS + e-mail válido pro Let's Encrypt.

## Setup

```bash
cd ansible
cp inventory.example.ini inventory.ini
# edite inventory.ini: ansible_host, ansible_user, ansible_ssh_private_key_file,
# ansible_port — usando o que o wizard mostrou nas etapas Users/SSH
```

`inventory.ini` é gitignored (fica só na sua máquina, tem IP/usuário reais
da sua VPS).

```bash
cp group_vars/vps.yml.example group_vars/vps.yml
# edite: traefik_dashboard_host, portainer_host, traefik_acme_email
# (e traefik_acme_ca_server pra producao, quando o DNS ja resolver)
```

`group_vars/vps.yml` também é gitignored — aplica automaticamente a todo
host do grupo `[vps]` (convenção do Ansible: nome do arquivo == nome do
grupo). Sem esse arquivo, os placeholders fictícios de
`roles/traefik/defaults/main.yml` continuam valendo.

## Uso

```bash
ansible-playbook site.yml --ask-become-pass
```

`--ask-become-pass` pede a senha de sudo local que o wizard gerou na etapa
Users (campo `data.password`, mostrado uma vez só na UI) — o usuário criado
pelo server-safe não tem sudo sem senha (`NOPASSWD`), então o Ansible
precisa dela pra `become: true`.

Rodar de novo é seguro: cada role confere o que já existe (`docker
inspect`/`docker service inspect`/`docker network inspect`) antes de
criar, não recria o que já está no ar.

Pra rodar `site.yml` e `app.yml` numa passada só (depois de trocar os
placeholders de app), passa os dois — não precisa fundir os arquivos:
```bash
ansible-playbook site.yml app.yml --ask-become-pass
```

## O que cada role faz

- **docker**: instala Docker CE via repositório oficial (Debian/Ubuntu ou
  RHEL, mesma lógica do `ensure_docker` em `internal/scripts/common.sh`),
  habilita o serviço, inicializa modo swarm (manager único) e instala
  `server-safe-swarm-recovery.service`: no boot, espera o swarm ficar
  ativo + 60s e dá `docker service update --force` só nos services com
  réplicas abaixo do desejado (o swarm às vezes falha tasks com "No such
  container" logo depois de um reboot e não retenta).
- **traefik**: sobe o service `traefik:v3.1` na rede overlay
  `server-safe-proxy`, publica só 80/443. Dashboard roteado por domínio +
  basicauth (credencial gerada e mostrada uma vez na criação). Usa o
  provider **`--providers.swarm`** do Traefik v3 (`providers.docker.swarmMode`
  foi removido no v3 e derruba o Traefik em crash loop). O hash do
  basicauth é validado antes de subir: basicauth com usuários vazios faz o
  Traefik v3 entrar em panic e parar de aplicar qualquer config nova.

> Se você já tinha rodado uma versão anterior deste role (com
> `--providers.docker.swarmmode`), o service existente não é recriado
> sozinho (o role só cria se não existir). Rode `docker service rm traefik`
> na VPS e depois o `site.yml` de novo: o volume `traefik_letsencrypt`
> (certificados) é preservado.
- **portainer**: sobe o service `portainer-ce:lts` na mesma rede, sem
  porta publicada — roteado pelo traefik por domínio.

`site.yml` roda só esses três — funciona sozinho, com imagens reais, sem
precisar de nada além do que já está aqui.

## app.yml — stack de aplicação (Database + API + Frontend)

**Template, não algo pra rodar como está.** `api`/`frontend` usam imagens
fictícias (`registry.example.com/...`) — não existe "imagem genérica de
API", você troca pela imagem real do seu projeto antes de rodar. Rode
`ansible-playbook app.yml --ask-become-pass` só depois disso, separado do
`site.yml` (que continua funcionando puro, infra sem app nenhum).

Topologia (cenário de 1 node — 3+ nodes é um estudo à parte, ainda não
implementado aqui):

```
        server-safe-proxy (overlay, publica via traefik)
   ┌──────────┬──────────┬──────────┐
traefik    frontend      api       portainer
                           │
                    app-data (overlay, privada)
                           │
                        database
```

- **database**: `postgres:16-alpine` (imagem real, não placeholder — banco
  genérico faz sentido, API/Frontend não). `--replicas 1`, travado no node
  via `--constraint node.labels.tier==db` (label posto em `self` — o único
  node hoje). Só entra na rede `app-data`, nunca em `server-safe-proxy`,
  sem label de traefik — inalcançável de fora e do próprio traefik. Senha
  gerada uma vez e **persistida** em `credentials/database_password` no
  seu control node (gitignored) — diferente da senha do dashboard do
  traefik (mostrada uma vez só, nunca salva): esta o `api` precisa reler
  em toda execução, é credencial máquina-a-máquina, não humana.
- **api**: entra em **duas** redes — `server-safe-proxy` (traefik roteia
  até ela) e `app-data` (fala com `database` pelo nome, DNS interno do
  overlay). Sem `--constraint`: stateless, o scheduler bota em qualquer
  node. `DATABASE_URL` é só um exemplo de convenção (12-factor) — ajuste
  pro que seu framework/ORM espera.
- **frontend**: só `server-safe-proxy`. Sem acesso à rede do banco.

Todos os três (e o `traefik`/`portainer`) usam o mesmo padrão de
idempotência: `docker service inspect <nome>` decide se cria, rerun é
seguro.

**Por que banco não replica sozinho / por que `--constraint`**: `replicas
N` num banco cria N bancos *independentes* (dado divergente, não um
cluster sincronizado) — swarm não entende protocolo de replicação nenhum,
só sobe containers idênticos. Volume `local` é por node: se a task
reagendar em outro node sem constraint, sobe um volume novo *vazio* com o
mesmo nome, silenciosamente (não é erro, não avisa). Por isso 1 réplica só
+ travada no node certo. Isso NÃO dá HA de verdade (se esse node cair, o
serviço fica fora do ar até voltar) — HA de banco de verdade precisa da
replicação própria do banco (streaming replication etc.), fora do escopo
deste template.

### Rotacionar a senha do banco

O Postgres só lê `POSTGRES_PASSWORD` na **primeira** inicialização do
volume; depois disso a senha vive dentro de `database_data`. Trocar só o
arquivo `credentials/database_password` (ou a env do service) não muda a
senha do banco e derruba a API. Por isso os roles `database` e `api`
**falham** se o arquivo de credencial sumir enquanto o volume já existe,
em vez de gerar uma senha nova em silêncio. Para rotacionar:

```bash
# 1. Na VPS: trocar a senha DENTRO do banco primeiro
docker exec -it $(docker ps -q -f name=database) \
  psql -U app -c "ALTER USER app PASSWORD 'NOVA_SENHA';"
# 2. No control node: gravar a mesma senha no arquivo
printf '%s' 'NOVA_SENHA' > ansible/credentials/database_password
# 3. Recriar só a api (o role so cria se nao existir)
docker service rm api   # na VPS
ansible-playbook app.yml --ask-become-pass
```

Guarde também uma cópia de `credentials/database_password` num gerenciador
de senhas: é a única cópia fora do banco.

## Operação: o que não fazer

Lições de incidentes reais em produção com esta mesma arquitetura:

- **Nunca** `docker service update --force traefik` para resolver um
  problema de *outro* service. Force update só no service afetado. Reiniciar
  o Traefik derruba o roteamento de todos.
- Antes de `docker stack deploy` com bind mount de **arquivo** novo, confira
  se o arquivo existe na VPS: se não existir, o Docker cria um *diretório*
  no lugar e o service quebra.
- Nunca edite YAML de config com `cat >>` (append): duplica chaves e
  corrompe o arquivo. Sobrescreva o arquivo inteiro.
- Labels de basicauth nunca podem ficar vazios (variável de ambiente não
  definida no deploy vira `basicauth.users=`). Se o Traefik responder 404
  para um service saudável e o log tiver `ERR Error in Go routine`, o
  ConfigurationWatcher morreu: corrija o label e só então reinicie o task
  do Traefik.
- Depois de um reboot, confira `docker service ls` (réplicas `0/1`); o
  `server-safe-swarm-recovery.service` cobre o caso comum, e
  `journalctl -u server-safe-swarm-recovery` mostra o que ele fez.

## Variáveis

Definidas em `roles/<nome>/defaults/main.yml` (imagem, domínios, usuário
do dashboard) e `group_vars/all.yml` (rede overlay compartilhada, nome do
banco/usuário — contrato entre `database` e `api`). Pra sobrescrever, use
`group_vars/vps.yml` ou `-e` na linha de comando — não precisa editar as
roles.
