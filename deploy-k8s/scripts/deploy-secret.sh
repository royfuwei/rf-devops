#!/usr/bin/env bash
set -euo pipefail

# 優先順序：由外部導出的 PROJECT，若無則回退到 NAMESPACE (保持相容性)
PROJECT="${PROJECT:-$NAMESPACE}" 
NAMESPACE="${NAMESPACE:-test}"
ENV_NAME="${ENV_NAME:-NewK8s}"
SERVICE_NAME="${SERVICE_NAME:-}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "Using project folder: $PROJECT"
echo "Target namespace: $NAMESPACE"
echo "Using env: $ENV_NAME"
echo "Service: ${SERVICE_NAME:-<none>}"

# 確保 namespace 存在
kubectl get namespace "$NAMESPACE" &>/dev/null || kubectl create namespace "$NAMESPACE"

apply_docker_registry_secret() {
  local name="$1"
  if [[ -z "${HARBOR_HOST:-}" || -z "${HARBOR_USERNAME:-}" || -z "${HARBOR_TOKEN:-}" ]]; then
    return 0
  fi
  kubectl -n "$NAMESPACE" create secret docker-registry "$name" \
    --docker-server="$HARBOR_HOST" \
    --docker-username="$HARBOR_USERNAME" \
    --docker-password="$HARBOR_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
}

apply_docker_registry_secret "harbor-registry-secret"

if [[ -z "$SERVICE_NAME" ]]; then exit 0; fi

ENV_DIR="${REPO_ROOT}/${PROJECT}/env/${ENV_NAME}/env_keys"
KEYS_FILE="${ENV_DIR}/${SERVICE_NAME}.secrets.keys"
COMMON_KEYS_FILE="${ENV_DIR}/common.secrets.keys"

if [[ ! -f "$KEYS_FILE" ]]; then
  echo "ℹ️ No keys file found at $KEYS_FILE. Skipping."
  exit 0
fi

# 使用關聯數組去重
declare -A MAPPED_KEYS

process_keys() {
  local file="$1"
  [ ! -f "$file" ] && return
  echo "📖 Reading keys from $(basename "$file")..."
  while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    
    # 清除 Windows 換行符號
    clean_line=$(echo "$line" | tr -d '\r')
    
    if [[ "$clean_line" == *":"* ]]; then
      env_var_name="${clean_line%%:*}"
      secret_key_name="${clean_line#*:}"
    else
      env_var_name="$clean_line"
      secret_key_name="$clean_line"
    fi

    val="${!env_var_name:-}"
    if [[ -z "$val" ]]; then
      echo "❌ Missing required env var: $env_var_name"
      exit 1
    fi

    MAPPED_KEYS["$secret_key_name"]="$val"
    echo "  ✅ Prepared $env_var_name -> $secret_key_name"
  done < "$file"
}

process_keys "$COMMON_KEYS_FILE"
process_keys "$KEYS_FILE"

# --- 核心改變：改用 --from-literal 構建指令 ---
SECRET_NAME="${SERVICE_NAME}-env"
CMD="kubectl -n $NAMESPACE create secret generic $SECRET_NAME --dry-run=client -o yaml"

echo "🔸 Generating Secret command from ${#MAPPED_KEYS[@]} unique keys..."
for key in "${!MAPPED_KEYS[@]}"; do
  # 使用 --from-literal 避開暫存檔重複 Key 的解析風險
  # 注意：這裡使用 printf %q 來處理可能存在的特殊字元
  CMD+=" --from-literal=$(printf %q "$key")=$(printf %q "${MAPPED_KEYS[$key]}")"
done

if eval "$CMD" | kubectl apply -f -; then
  echo "✅ Secret '$SECRET_NAME' applied successfully."
else
  echo "❌ Failed to apply secret '$SECRET_NAME'."
  exit 1
fi