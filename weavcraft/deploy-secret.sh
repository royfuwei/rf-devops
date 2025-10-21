#!/bin/bash

# 預設 namespace
NAMESPACE="${NAMESPACE:-weavcraft}"
echo "Using namespace: $NAMESPACE"

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
  --from-literal=DB_MONGO_URI=$ENV_DB_MONGO_URI \
  --from-literal=PUBLIC_SUPABASE_URL=$ENV_PUBLIC_SUPABASE_URL \
  --from-literal=PUBLIC_SUPABASE_ANON_KEY=$ENV_PUBLIC_SUPABASE_ANON_KEY \
  --from-literal=JWT_SECRET=$ENV_JWT_SECRET \
  --from-literal=JWT_EXPIRES_IN=$ENV_JWT_EXPIRES_IN
