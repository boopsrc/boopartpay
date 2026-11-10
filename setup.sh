#!/usr/bin/env bash
# Setup do ambiente de teste boopartpay (Linux / macOS).
# Clona booprecognition e boopateway, configura e sobe tudo no Docker.
# Uso: ./setup.sh   (ou: bash setup.sh)
set -euo pipefail

# ---------------------------------------------------------------- config de teste
JWT_SECRET="${BOOP_JWT_SECRET:-boopartpay-test-jwt-secret-0123456789abcdefghij}"
CLIENT_ID="boop-admin"
CLIENT_SECRET="${BOOP_CLIENT_ADMIN_SECRET:-boopartpay-test-admin-secret}"
ADMIN_SCOPE="${BOOP_ADMIN_SCOPE:-identify persons:write persons:delete}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-teste123}"
RECOGNITION_URL="http://localhost:31900"
WAIT_SECONDS=600

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$ROOT/workspace"
REC_DIR="$WORKSPACE/booprecognition"
GATE_DIR="$WORKSPACE/boopateway"

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31mERRO: %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- 1. pre-requisitos
step "Verificando pré-requisitos"
for cmd in git docker curl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' não encontrado no PATH"
done
docker compose version >/dev/null 2>&1 || fail "'docker compose' (v2) não disponível"
docker info >/dev/null 2>&1 || fail "o Docker não está rodando (ou falta permissão: use sudo ou entre no grupo docker)"

# ---------------------------------------------------------------- 2. clonar / atualizar
step "Clonando/atualizando repositórios"
mkdir -p "$WORKSPACE"
clone_or_pull() {
  local name="$1" url="$2" dir="$WORKSPACE/$1"
  if [ -d "$dir/.git" ]; then
    echo "$name já existe, atualizando"
    git -C "$dir" checkout -- .        # desfaz o patch do config.yaml antes do pull
    git -C "$dir" pull --ff-only
  else
    git clone "$url" "$dir"
  fi
}
clone_or_pull booprecognition https://github.com/boopsrc/booprecognition.git
clone_or_pull boopateway      https://github.com/boopsrc/boopateway.git

# ---------------------------------------------------------------- 3. config.yaml -> sqlite
step "Configurando booprecognition para SQLite"
sed -i.bak -E 's/^target:.*/target: sqlite/' "$REC_DIR/config.yaml"   # -i.bak: GNU e BSD
rm -f "$REC_DIR/config.yaml.bak"

# ---------------------------------------------------------------- 4. .env do booprecognition
printf 'BOOP_JWT_SECRET=%s\nBOOP_CLIENT_ADMIN_SECRET=%s\n' "$JWT_SECRET" "$CLIENT_SECRET" > "$REC_DIR/.env"

# ---------------------------------------------------------------- 5. subir booprecognition
step "Subindo booprecognition (o primeiro build baixa os modelos e demora)"
docker compose -p booprecognition -f "$ROOT/docker/booprecognition.compose.yml" up -d --build

# ---------------------------------------------------------------- 6. aguardar e pegar token
step "Aguardando booprecognition em $RECOGNITION_URL e emitindo token"
TOKEN=""
deadline=$(( $(date +%s) + WAIT_SECONDS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  resp="$(curl -s --max-time 10 -u "$CLIENT_ID:$CLIENT_SECRET" \
            -d grant_type=client_credentials "$RECOGNITION_URL/oauth/token" || true)"
  TOKEN="$(printf '%s' "$resp" | sed -n 's/.*"access_token" *: *"\([^"]*\)".*/\1/p')"
  [ -n "$TOKEN" ] && break
  printf '.'
  sleep 5
done
echo
if [ -z "$TOKEN" ]; then
  docker logs booprecognition --tail 50 || true
  fail "booprecognition não respondeu em ${WAIT_SECONDS}s"
fi
echo "Token obtido."

# ---------------------------------------------------------------- 7. .env do boopateway
#    BOOP_TOKEN: token fixo usado pela API; ADMIN_PASSWORD: login do portal;
#    BOOP_CLIENT_*: a cada login do portal a API gera um token novo via OAuth.
cat > "$GATE_DIR/.env" <<EOF
BOOP_TOKEN=$TOKEN
ADMIN_PASSWORD=$ADMIN_PASSWORD
ADMIN_BOOP_TOKEN=
BOOP_CLIENT_ID=$CLIENT_ID
BOOP_CLIENT_SECRET=$CLIENT_SECRET
BOOP_ADMIN_SCOPE="$ADMIN_SCOPE"
EOF

# ---------------------------------------------------------------- 8. subir boopateway
step "Subindo boopateway (API + portal)"
(cd "$GATE_DIR" && docker compose up -d --build)

# ---------------------------------------------------------------- 9. subir demo
step "Subindo demo de reconhecimento facial"
docker compose -p boopdemo -f "$ROOT/docker/demo.compose.yml" up -d --build

# ---------------------------------------------------------------- 10. resumo
step "Ambiente pronto"
echo "demo (reconhecimento):     http://localhost:31910"
echo "booprecognition (Swagger): $RECOGNITION_URL/docs"
echo "boopateway API:            http://localhost:31800"
echo "boopateway portal:         http://localhost:31801"
echo "senha do portal:           $ADMIN_PASSWORD"
echo "client_id / secret:        $CLIENT_ID / $CLIENT_SECRET"
echo "scopes do portal:          $ADMIN_SCOPE"
echo "BOOP_TOKEN:                $TOKEN"
