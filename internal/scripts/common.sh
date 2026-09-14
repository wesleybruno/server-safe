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
