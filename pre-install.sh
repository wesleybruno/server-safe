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

  echo "==> baixando go $GO_VERSION ($GO_ARCH)"
  curl -fsSL "$URL" -o "$TMP_DIR/$TARBALL"

  if curl -fsSL "$URL.sha256" -o "$TMP_DIR/$TARBALL.sha256" 2>/dev/null; then
    echo "$(cat "$TMP_DIR/$TARBALL.sha256")  $TMP_DIR/$TARBALL" | sha256sum -c - >/dev/null \
      || { echo "checksum do tarball do go nao confere, abortando" >&2; exit 1; }
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
