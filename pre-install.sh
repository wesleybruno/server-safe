#!/usr/bin/env bash
# Bootstrap para maquina totalmente nova, antes do install.sh: atualiza os
# pacotes do sistema e instala a toolchain Go que install.sh exige.
#
# uso: sudo bash pre-install.sh
set -euo pipefail

GO_VERSION="${GO_VERSION:-1.23.4}"

if [[ $EUID -ne 0 ]]; then
  echo "rode como root: sudo bash pre-install.sh" >&2
  exit 1
fi

echo "==> sincronizando relogio"
# Maquina nova recem-provisionada costuma subir com o relogio atrasado alguns
# minutos (antes do primeiro sync NTP) — isso faz o apt rejeitar o
# InRelease do repositorio com "not valid yet" e o script abortar (set -e).
if command -v timedatectl &>/dev/null; then
  timedatectl set-ntp true 2>/dev/null || true
  systemctl restart systemd-timesyncd 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    timedatectl status 2>/dev/null | grep -qi "System clock synchronized: yes" && break
    sleep 1
  done
fi

echo "==> atualizando pacotes do sistema"
if command -v apt-get &>/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates
elif command -v dnf &>/dev/null; then
  dnf upgrade -y -q
  dnf install -y -q curl ca-certificates
elif command -v yum &>/dev/null; then
  yum update -y -q
  yum install -y -q curl ca-certificates
else
  echo "gerenciador de pacotes nao suportado (apt-get/dnf/yum)" >&2
  exit 1
fi

if command -v go &>/dev/null; then
  echo "==> go ja instalado: $(go version)"
else
  case "$(uname -m)" in
    x86_64)  GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    *) echo "arquitetura nao suportada para instalar go: $(uname -m)" >&2; exit 1 ;;
  esac

  TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
  URL="https://go.dev/dl/$TARBALL"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  if ! getent hosts go.dev &>/dev/null; then
    echo "aviso: DNS nao resolve go.dev — confira /etc/resolv.conf e a rede antes de tentar de novo" >&2
  fi

  echo "==> baixando go $GO_VERSION ($GO_ARCH)"
  curl -fsSL "$URL" -o "$TMP_DIR/$TARBALL"

  # go.dev/dl/<arquivo>.sha256 redireciona pra uma pagina HTML, nao serve o
  # hash cru — dl.google.com (o storage por tras do go.dev/dl) serve. Compara
  # na mao em vez de `sha256sum -c` pra nao depender do formato exato do
  # arquivo remoto (so o hash, sem nome de arquivo junto).
  if curl -fsSL "https://dl.google.com/go/$TARBALL.sha256" -o "$TMP_DIR/$TARBALL.sha256" 2>/dev/null; then
    EXPECTED_SHA=$(awk '{print $1}' "$TMP_DIR/$TARBALL.sha256")
    ACTUAL_SHA=$(sha256sum "$TMP_DIR/$TARBALL" | awk '{print $1}')
    if [[ -z "$EXPECTED_SHA" || "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
      echo "checksum do tarball do go nao confere (esperado ${EXPECTED_SHA:-vazio}, obtido $ACTUAL_SHA), abortando" >&2
      exit 1
    fi
  else
    echo "aviso: nao consegui baixar o checksum oficial, seguindo sem verificar" >&2
  fi

  echo "==> instalando go em /usr/local/go"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$TMP_DIR/$TARBALL"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

  echo "==> go instalado: $(/usr/local/go/bin/go version)"
fi

echo "==> pronto. prossiga com: sudo bash install.sh"
