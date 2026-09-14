# Idempotent: safe to re-run for the same SS_USERNAME.

: "${SS_USERNAME:?missing SS_USERNAME}"
GENERATE_KEY="${SS_GENERATE_KEY:-false}"
PUBLIC_KEY="${SS_PUBLIC_KEY:-}"
KEY_OUT_DIR="${SS_KEY_OUT_DIR:-}"

echo "==> validando usuario '$SS_USERNAME'"
if [[ ! "$SS_USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  fail "username invalido: $SS_USERNAME"
fi

if id "$SS_USERNAME" &>/dev/null; then
  echo "==> usuario ja existe, pulando useradd"
else
  echo "==> criando usuario $SS_USERNAME"
  if getent group sudo &>/dev/null; then
    SUDO_GROUP="sudo"
  elif getent group wheel &>/dev/null; then
    SUDO_GROUP="wheel"
  else
    fail "nenhum grupo sudo/wheel encontrado"
  fi
  useradd -m -s /bin/bash -G "$SUDO_GROUP" "$SS_USERNAME"
fi

# Senha local so pra sudo/su — SSH continua so por chave, isso nao mexe em
# PasswordAuthentication. Gera sempre que a conta ainda nao tem uma senha
# usavel (usuario novo, OU usuario que ja existia mas nunca teve senha —
# ex: criado numa versao anterior desta ferramenta, antes dessa feature
# existir). Nao mexe se ja tiver senha de verdade (status "P").
PASSWORD=""
PW_STATUS=$(passwd -S "$SS_USERNAME" 2>/dev/null | awk '{print $2}')
if [[ "$PW_STATUS" != "P" ]]; then
  PASSWORD=$(random_password)
  echo "$SS_USERNAME:$PASSWORD" | chpasswd
  echo "==> senha local gerada para sudo/su (veja o campo na UI — nao e reexibida depois)"
else
  echo "==> usuario ja tem senha local definida, nao mexendo"
fi

HOME_DIR=$(getent passwd "$SS_USERNAME" | cut -d: -f6)
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

FINGERPRINT=""

if [[ "$GENERATE_KEY" == "true" ]]; then
  [[ -n "$KEY_OUT_DIR" ]] || fail "SS_KEY_OUT_DIR nao definido para geracao de chave"
  mkdir -p "$KEY_OUT_DIR"
  chmod 700 "$KEY_OUT_DIR"
  KEY_PATH="$KEY_OUT_DIR/id_ed25519"
  echo "==> gerando par de chaves ed25519"
  ssh-keygen -t ed25519 -N "" -f "$KEY_PATH" -C "$SS_USERNAME@server-safe" >/dev/null
  PUBLIC_KEY=$(cat "$KEY_PATH.pub")
  FINGERPRINT=$(ssh-keygen -lf "$KEY_PATH.pub" | awk '{print $2}')
  echo "==> chave gerada, fingerprint: $FINGERPRINT"
elif [[ -n "$PUBLIC_KEY" ]]; then
  echo "==> usando chave publica fornecida"
  FINGERPRINT=$(printf '%s' "$PUBLIC_KEY" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}' || true)
  [[ -n "$FINGERPRINT" ]] || fail "chave publica fornecida e invalida"
else
  fail "nenhuma chave fornecida (nem gerada nem importada)"
fi

if ! grep -qxF "$PUBLIC_KEY" "$AUTH_KEYS" 2>/dev/null; then
  echo "$PUBLIC_KEY" >> "$AUTH_KEYS"
  echo "==> chave publica adicionada ao authorized_keys"
else
  echo "==> chave publica ja presente, pulando"
fi

# useradd -m cria um grupo privado com o mesmo nome do usuario por padrao
# (Debian/Ubuntu/RHEL); assume-se essa convencao aqui.
chown -R "$SS_USERNAME:$SS_USERNAME" "$SSH_DIR"
chmod 600 "$AUTH_KEYS"

echo "==> validando"
id "$SS_USERNAME" >/dev/null || fail "usuario nao foi criado corretamente"
grep -qxF "$PUBLIC_KEY" "$AUTH_KEYS" || fail "chave nao esta em authorized_keys"

echo "==> ok"
result "ok" "usuario $SS_USERNAME pronto" "{\"username\":\"$SS_USERNAME\",\"fingerprint\":\"$FINGERPRINT\",\"password\":\"$(json_escape "$PASSWORD")\"}"
