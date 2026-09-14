#!/usr/bin/env bash
# Shared helpers, concatenated (via scripts.Combine) before every module
# script fed to bash on stdin. Not runnable standalone.
set -euo pipefail

result() {
  local status="$1" detail="$2" data="$3"
  # `data="${3:-{}}"` (o jeito "obvio") parseia errado: o bash acha o `}`
  # de dentro do valor-padrao como o fechamento do `${...}`, sobra um `}`
  # solto grudado no fim — quebra o data de QUALQUER chamada, nao so
  # quando o default entra em jogo. `if` em vez de expansao evita a
  # armadilha de parsing.
  if [[ -z "$data" ]]; then
    data="{}"
  fi
  printf 'RESULT_JSON:{"status":"%s","detail":"%s","data":%s}\n' "$status" "$detail" "$data"
}

fail() {
  echo "ERRO: $1" >&2
  result "error" "$1" "{}"
  exit 1
}

# random_password: 20 chars, sem caracteres ambiguos (sem 0/O/1/l/I) pra
# facilitar copiar/ler na tela. $RANDOM (builtin do bash) em vez de
# /dev/urandom + head: sob o `set -o pipefail` acima, head fechando o pipe
# cedo manda SIGPIPE pro gerador e aborta o script.
random_password() {
  local chars='ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
  local pass="" i
  for ((i = 0; i < 20; i++)); do
    pass+="${chars:RANDOM % ${#chars}:1}"
  done
  printf '%s' "$pass"
}

# json_escape <string> -> safe to embed inside a JSON string literal
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  printf '%s' "$s"
}

# ensure_installed <check-cmd> <apt-pkg> [dnf-pkg]
ensure_installed() {
  local check_cmd="$1" apt_pkg="$2" dnf_pkg="${3:-$2}"
  if command -v "$check_cmd" &>/dev/null; then return 0; fi
  if command -v apt-get &>/dev/null; then
    echo "==> instalando $apt_pkg via apt-get"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$apt_pkg"
  elif command -v dnf &>/dev/null; then
    echo "==> instalando $dnf_pkg via dnf"
    dnf install -y -q "$dnf_pkg"
  elif command -v yum &>/dev/null; then
    echo "==> instalando $dnf_pkg via yum"
    yum install -y -q "$dnf_pkg"
  else
    fail "gerenciador de pacotes nao suportado (apt-get/dnf/yum)"
  fi
}

# distro_family: echoes "debian" or "rhel"
distro_family() {
  if command -v apt-get &>/dev/null; then
    echo "debian"
  elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
    echo "rhel"
  else
    fail "distro nao suportada (nem apt-get nem dnf/yum)"
  fi
}

# ensure_docker: instala e habilita o Docker via repositorio oficial se
# ainda nao estiver presente (idempotente, no-op se ja tiver). Usado tanto
# pelo botao "instalar docker" (docker-install.sh) quanto por qualquer
# extra que dependa dele (Portainer, Traefik) — nesses casos roda como
# parte da instalacao pedida, sem show de erro separado: so mais linhas
# de log, a dependencia resolve sozinha.
ensure_docker() {
  if command -v docker &>/dev/null; then
    return 0
  fi

  local family
  family=$(distro_family)

  if [[ "$family" == "debian" ]]; then
    echo "==> instalando docker via repositorio oficial (apt)"
    ensure_installed curl curl
    ensure_installed gpg gnupg

    install -m 0755 -d /etc/apt/keyrings
    . /etc/os-release
    curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    local arch
    arch=$(dpkg --print-architecture)
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
      > /etc/apt/sources.list.d/docker.list

    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      docker-ce docker-ce-cli containerd.io docker-compose-plugin
  else
    echo "==> instalando docker via repositorio oficial (dnf/yum)"
    if command -v dnf &>/dev/null; then
      dnf -y -q install dnf-plugins-core
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      dnf install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
      yum install -y -q yum-utils
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      yum install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi
  fi

  echo "==> habilitando servico docker"
  systemctl enable --now docker

  systemctl is-active --quiet docker || fail "servico docker nao esta ativo apos instalar"
  command -v docker &>/dev/null || fail "binario docker nao encontrado apos instalar"
}
