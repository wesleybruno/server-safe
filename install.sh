#!/usr/bin/env bash
# Bootstrap para maquina nova: baixa o binario pre-compilado do ultimo
# release (sem precisar de Go na maquina alvo); se nao houver release
# publicado ainda, cai pra compilar a partir deste repo. Sobe como servico
# systemd, escutando so em localhost.
#
# uso: sudo bash install.sh   (rodar de dentro do repo clonado)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "rode como root: sudo bash install.sh" >&2
  exit 1
fi

REPO_SLUG="wesleybruno/server-safe"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="/usr/local/bin/server-safe"

case "$(uname -m)" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)       ARCH="" ;;
esac

DOWNLOADED=false
if [[ -n "$ARCH" ]] && command -v curl &>/dev/null; then
  RELEASE_URL="https://github.com/$REPO_SLUG/releases/latest/download/server-safe-linux-$ARCH"
  echo "==> tentando baixar binario pronto (linux/$ARCH)"
  if curl -fsSL "$RELEASE_URL" -o "$BIN_PATH.tmp"; then
    mv "$BIN_PATH.tmp" "$BIN_PATH"
    DOWNLOADED=true
    echo "==> baixado de $RELEASE_URL"
  else
    rm -f "$BIN_PATH.tmp"
    echo "==> nenhum release disponivel ainda, compilando localmente"
  fi
fi

if [[ "$DOWNLOADED" != "true" ]]; then
  if ! command -v go &>/dev/null; then
    echo "go nao encontrado nesta maquina e nao ha binario pronto pra baixar." >&2
    echo "instale o go antes de continuar (sudo bash pre-install.sh resolve) ou:" >&2
    echo "  https://go.dev/doc/install" >&2
    exit 1
  fi
  echo "==> compilando"
  (cd "$REPO_DIR" && go build -o "$BIN_PATH" ./cmd/server)
fi

chmod 755 "$BIN_PATH"

echo "==> instalando servico systemd"
cat > /etc/systemd/system/server-safe.service <<'EOF'
[Unit]
Description=server-safe - wizard de configuracao inicial
After=network.target

[Service]
ExecStart=/usr/local/bin/server-safe --addr 127.0.0.1:8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now server-safe

echo "==> pronto"
echo "acesse via tunel SSH (a maquina so escuta em localhost):"
echo "  ssh -L 8080:127.0.0.1:8080 usuario@este-servidor"
echo "depois abra http://127.0.0.1:8080 no navegador local"
