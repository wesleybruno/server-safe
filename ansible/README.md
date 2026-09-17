# ansible/

Playbooks pra configurar uma VPS já hardenizada pelo wizard server-safe,
rodados **da máquina do admin** (não do binário Go, não da própria VPS).
Complementa o wizard, não substitui: o server-safe cuida do hardening
inicial (users/SSH/firewall/fail2ban/updates) de forma zero-dependency
(binário único, sem exigir nada instalado na VPS além de bash); estes
playbooks cuidam da configuração de infra recorrente (Docker, Traefik,
Portainer, e o que vier depois) e exigem Ansible + Python na sua máquina
de controle (a VPS só precisa do Python que o Ansible já exige de
qualquer managed node).

## Pré-requisitos

- Ansible instalado na sua máquina (`pip install ansible` ou pacote da distro).
- VPS já passou pelas etapas **Users** e **SSH** do wizard server-safe —
  precisamos do usuário sudo + chave privada que ele gerou.

## Setup

```bash
cd ansible
cp inventory.example.ini inventory.ini
# edite inventory.ini: ansible_host, ansible_user, ansible_ssh_private_key_file,
# ansible_port — usando o que o wizard mostrou nas etapas Users/SSH
```

`inventory.ini` é gitignored (fica só na sua máquina, tem IP/usuário reais
da sua VPS).

## Uso

```bash
ansible-playbook site.yml --ask-become-pass
```

`--ask-become-pass` pede a senha de sudo local que o wizard gerou na etapa
Users (campo `data.password`, mostrado uma vez só na UI) — o usuário criado
pelo server-safe não tem sudo sem senha (`NOPASSWD`), então o Ansible
precisa dela pra `become: true`.

Rodar de novo é seguro: cada role confere o que já existe (`docker inspect`)
antes de instalar/subir container, não recria o que já está no ar.

## O que cada role faz

- **docker**: instala Docker CE via repositório oficial (Debian/Ubuntu ou
  RHEL, mesma lógica do `ensure_docker` em `internal/scripts/common.sh`),
  habilita o serviço.
- **traefik**: sobe o container `traefik:v3.1`, portas 80/443 públicas,
  dashboard em `127.0.0.1:8090` (acesse via túnel SSH). Cria a rede Docker
  `server-safe-proxy` pra containers de app futuros se conectarem e serem
  roteados via labels do Traefik.
- **portainer**: sobe `portainer/portainer-ce:lts`, mgmt UI em
  `127.0.0.1:9443` (túnel SSH).

Portas seguem o mesmo mapa do wizard (ver `CLAUDE.md` na raiz do repo) —
loopback-only, nunca `0.0.0.0`, pra não colidir com o painel server-safe
nem com os outros extras.

## Variáveis

Definidas em `roles/<nome>/defaults/main.yml` (imagem, portas, nome da
rede). Pra sobrescrever, use `group_vars/vps.yml` ou `-e` na linha de
comando — não precisa editar as roles.
