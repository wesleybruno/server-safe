# Idempotente: reusa o deployment se ja existir (checa o container do
# frontend). Requer Docker com o plugin compose v2 — instala junto
# (ensure_docker, common.sh) se ainda nao tiver.
#
# O extra mais pesado do grupo: ClickHouse + Postgres + collector + migrator
# + keeper + frontend, 6 containers no total — recomenda pelo menos 4GB de
# RAM livres antes de instalar. Instalado via `foundryctl`, a ferramenta
# oficial do projeto SigNoz (sucessora do antigo `docker-compose` direto, que
# o proprio projeto descontinuou em favor dela) — nao reimplementamos o
# compose na mao porque o schema do ClickHouse/migrator e acoplado a versao
# e fragil de manter fora da ferramenta oficial. `foundryctl` gera o compose
# num diretorio proprio (`pours/`) a partir de um `casting.yaml`; usamos
# `spec.patches` (JSON Patch) nesse arquivo pra forcar bind em loopback e
# tirar a porta do frontend do 8080 (colisao com o proprio painel).
command -v docker &>/dev/null || ensure_docker

SIGNOZ_DIR=/etc/server-safe/signoz
mkdir -p "$SIGNOZ_DIR"

if docker ps -a --format '{{.Names}}' | grep -qx signoz-signoz-0; then
  echo "==> signoz ja existe, garantindo que os containers estao rodando"
  for c in signoz-metastore-postgres-0 signoz-telemetrykeeper-clickhousekeeper-0 signoz-telemetrystore-clickhouse-0-0 ingester signoz-signoz-0; do
    docker start "$c" &>/dev/null || true
  done
else
  if ! command -v foundryctl &>/dev/null; then
    echo "==> instalando foundryctl (CLI oficial do SigNoz)"
    curl -fsSL https://signoz.io/foundry.sh | FOUNDRY_INSTALL_DIR=/usr/local/bin FOUNDRY_ASSUME_YES=true bash
  fi
  command -v foundryctl &>/dev/null || fail "foundryctl nao encontrado apos instalar"

  cat > "$SIGNOZ_DIR/casting.yaml" <<'EOF'
apiVersion: v1alpha1
metadata:
  name: signoz
spec:
  deployment:
    flavor: compose
    mode: docker
  patches:
    - target: "deployment/compose.yaml"
      operations:
        - op: replace
          path: /services/signoz-signoz-0/ports/0
          value: "127.0.0.1:8085:8080"
        - op: replace
          path: /services/ingester/ports/0
          value: "127.0.0.1:4317:4317"
        - op: replace
          path: /services/ingester/ports/1
          value: "127.0.0.1:4318:4318"
EOF

  echo "==> subindo stack signoz via foundryctl (baixa varias imagens, pode demorar)"
  (cd "$SIGNOZ_DIR" && foundryctl cast -f casting.yaml -p pours --format text)
fi

echo "==> validando"
sleep 5
docker ps --format '{{.Names}}' | grep -qx signoz-signoz-0 || fail "container signoz-signoz-0 nao esta rodando"

echo "==> ok"
result "ok" "signoz rodando — painel em http://127.0.0.1:8085 (acesse via tunel SSH). Primeiro boot pode levar alguns minutos ate ClickHouse/Postgres terminarem de inicializar. Ingestao OTLP (pra apontar apps que usam OpenTelemetry) em 127.0.0.1:4317 (grpc) e 127.0.0.1:4318 (http), mesma logica de tunel." "{\"url\":\"http://127.0.0.1:8085\"}"
