#!/usr/bin/env bash
# Bootstrap para maquina nova: compila o binario a partir deste repo e sobe
# como servico systemd, escutando so em localhost.
#
# uso: sudo bash install.sh   (rodar de dentro do repo clonado)
#
# TODO v2: distribuir binario pre-compilado via GitHub Releases para nao
# depender de toolchain go instalada na maquina alvo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "rode como root: sudo bash install.sh" >&2
  exit 1
fi

if ! command -v go &>/dev/null; then
  echo "go nao encontrado nesta maquina. instale antes de continuar:" >&2
  echo "  https://go.dev/doc/install" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="/usr/local/bin/server-safe"

echo "==> compilando"
(cd "$REPO_DIR" && go build -o "$BIN_PATH" ./cmd/server)
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
