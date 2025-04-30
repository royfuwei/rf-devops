#!/usr/bin/env bash
set -euo pipefail

# --- 1. 預設 namespace ---
if [ -z "${NAMESPACE:-}" ]; then
  echo "NAMESPACE is not set. Using default namespace."
  NAMESPACE="default"
fi
echo "Using namespace: $NAMESPACE"

# --- 2. Release 與 Chart 路徑 ---
RELEASE_NAME="$PROJECT_NAME"
CHART_PATH="oci://$HARBOR_HOST/$PROJECT_SOURCE/$PROJECT_NAME"

# --- 3. 登入 Harbor Registry ---
echo "🔐 Logging in to $HARBOR_HOST ..."
helm registry login \
  --username "$HARBOR_USERNAME" \
  --password "$HARBOR_TOKEN" \
  "$HARBOR_HOST"

# --- 4. 安裝或升級 Helm Release ---
VALUES_ARG=()
if [ -f "./values.yaml" ]; then
  echo "📄 Found values.yaml. Including it in Helm command."
  VALUES_ARG+=(--values ./values.yaml)
fi

HELM_OPTS=(
  "${VALUES_ARG[@]}"
  --wait
  --timeout=5m
  --atomic
  --namespace "$NAMESPACE"
  --create-namespace
)

if helm status "$RELEASE_NAME" --namespace "$NAMESPACE" > /dev/null 2>&1; then
  echo "⬆️ Release '$RELEASE_NAME' exists in namespace '$NAMESPACE'. Upgrading..."
  helm upgrade "$RELEASE_NAME" "$CHART_PATH" "${HELM_OPTS[@]}"
else
  echo "🚀 Release '$RELEASE_NAME' does not exist. Installing..."
  helm install "$RELEASE_NAME" "$CHART_PATH" "${HELM_OPTS[@]}"
fi

echo "✅ Helm release '$RELEASE_NAME' has been successfully installed or upgraded in namespace '$NAMESPACE'."