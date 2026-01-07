#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"
ENV_NAME="${ENV_NAME:-k8s-royfuwei}"          # 對應 rfjs/env/<ENV_NAME>/
SERVICE_NAME="${SERVICE_NAME:-}"               # 例如 api
ROOT_DIR="${ROOT_DIR:-.}"                      # 允許從任意 cwd 執行

echo "Using namespace: $NAMESPACE"
echo "Using env: $ENV_NAME"
echo "Service: ${SERVICE_NAME:-<none>}"

# 確保 namespace 存在
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "🔸 Namespace '$NAMESPACE' not found. Creating..."
  kubectl create namespace "$NAMESPACE"
else
  echo "🔸 Namespace '$NAMESPACE' already exists."
fi

apply_docker_registry_secret() {
  local name="$1"
  echo "🔸 Applying docker-registry secret '$name'..."
  kubectl -n "$NAMESPACE" create secret docker-registry "$name" \
    --docker-server="${HARBOR_HOST:?missing HARBOR_HOST}" \
    --docker-username="${HARBOR_USERNAME:?missing HARBOR_USERNAME}" \
    --docker-password="${HARBOR_TOKEN:?missing HARBOR_TOKEN}" \
    --docker-email="${HARBOR_EMAIL:-}" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "✅ Secret '$name' applied."
}

# 1) registry secret（共用）
apply_docker_registry_secret "harbor-registry-secret"

# 沒指定 service 就結束（只更新 registry secret）
if [[ -z "$SERVICE_NAME" ]]; then
  echo "ℹ️ SERVICE_NAME not set; skip service env secrets."
  exit 0
fi

ENV_DIR="${ROOT_DIR}/rfjs/env/${ENV_NAME}"
KEYS_FILE="${ENV_DIR}/${SERVICE_NAME}.secrets.keys"
COMMON_KEYS_FILE="${ENV_DIR}/common.secrets.keys"

if [[ ! -f "$KEYS_FILE" ]]; then
  echo "❌ keys file not found: $KEYS_FILE"
  exit 1
fi

# 讀 keys（忽略空白與 # 註解）
read_keys() {
  local file="$1"
  grep -v '^\s*$' "$file" | grep -v '^\s*#' | sed 's/\r$//'
}

# 產生暫存 env file（KEY=VALUE）
TMP_ENV_FILE="$(mktemp)"
cleanup() { rm -f "$TMP_ENV_FILE"; }
trap cleanup EXIT

# 合併 common + service keys（common 可不存在）
ALL_KEYS=""
if [[ -f "$COMMON_KEYS_FILE" ]]; then
  ALL_KEYS="$( (read_keys "$COMMON_KEYS_FILE"; read_keys "$KEYS_FILE") | awk '!seen[$0]++' )"
else
  ALL_KEYS="$(read_keys "$KEYS_FILE")"
fi

if [[ -z "$ALL_KEYS" ]]; then
  echo "❌ No keys found in $KEYS_FILE"
  exit 1
fi

echo "🔸 Required keys:"
echo "$ALL_KEYS" | sed 's/^/  - /'

# 將環境變數寫入 env file
while IFS= read -r key; do
  # 使用 indirect expansion 取環境變數值
  val="${!key:-}"
  if [[ -z "$val" ]]; then
    echo "❌ Missing required env var: $key"
    exit 1
  fi
  # 注意：這裡用 printf 避免特殊字元問題
  printf "%s=%s\n" "$key" "$val" >> "$TMP_ENV_FILE"
done <<< "$ALL_KEYS"

SECRET_NAME="${SERVICE_NAME}-env"
echo "🔸 Applying generic secret '$SECRET_NAME' from env file..."
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-env-file="$TMP_ENV_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Secret '$SECRET_NAME' applied."
