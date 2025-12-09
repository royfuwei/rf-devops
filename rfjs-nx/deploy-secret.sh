#!/bin/bash
set -euo pipefail

# 預設 namespace
NAMESPACE="${NAMESPACE:-default}"
echo "Using namespace: $NAMESPACE"

# 確保 namespace 存在
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "🔸 Namespace '$NAMESPACE' not found. Creating..."
  kubectl create namespace "$NAMESPACE"
else
  echo "🔸 Namespace '$NAMESPACE' already exists."
fi

# 通用函式：create 或 recreate secret
create_or_replace_secret() {
  local type=$1
  local name=$2
  shift 2
  echo "🔸 Creating secret '$name' ($type)..."
  if ! kubectl create secret "$type" "$name" -n "$NAMESPACE" "$@"; then
    if kubectl get secret "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
      echo "Secret '$name' already exists. Replacing..."
      kubectl delete secret "$name" -n "$NAMESPACE"
      kubectl create secret "$type" "$name" -n "$NAMESPACE" "$@" && echo "✅ Secret '$name' recreated."
    else
      echo "❌ Failed to create secret '$name' (not exists but creation failed)"
    fi
  else
    echo "✅ Secret '$name' created."
  fi
}

# Harbor docker-registry secret
create_or_replace_secret docker-registry "harbor-registry-secret" \
  --docker-server="$HARBOR_HOST" \
  --docker-username="$HARBOR_USERNAME" \
  --docker-password="$HARBOR_TOKEN" \
  --docker-email="$HARBOR_EMAIL"

# 環境變數 secret
create_or_replace_secret generic "env-secret" \
  --from-literal=DB_MONGO_URI="$ENV_DB_MONGO_URI" \
  --from-literal=PUBLIC_SUPABASE_URL="$ENV_PUBLIC_SUPABASE_URL" \
  --from-literal=PUBLIC_SUPABASE_ANON_KEY="$ENV_PUBLIC_SUPABASE_ANON_KEY" \
  --from-literal=LINE_CHANNEL_ID="$ENV_LINE_CHANNEL_ID" \
  --from-literal=LINE_CHANNEL_ACCESS_TOKEN="$ENV_LINE_CHANNEL_ACCESS_TOKEN" \
  --from-literal=LINE_CHANNEL_SECRET="$ENV_LINE_CHANNEL_SECRET" \
  --from-literal=LINE_NOTIFY_CLIENT_ID="$ENV_LINE_NOTIFY_CLIENT_ID" \
  --from-literal=LINE_NOTIFY_CLIENT_SECRET="$ENV_LINE_NOTIFY_CLIENT_SECRET"
