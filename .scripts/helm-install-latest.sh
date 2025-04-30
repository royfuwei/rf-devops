#!/usr/bin/env bash
set -euo pipefail

# --- 1. 預設 namespace ---
if [ -z "${NAMESPACE:-}" ]; then
  echo "NAMESPACE is not set. Using default namespace."
  NAMESPACE="default"
fi
echo "📛 Using namespace: $NAMESPACE"

# --- 2. Release 與 Chart 路徑 ---
RELEASE_NAME="$PROJECT_NAME"
CHART_PATH="oci://$HARBOR_HOST/$PROJECT_SOURCE/$PROJECT_NAME"

# --- 3. 登入 Harbor Registry ---
echo "🔐 Logging in to $HARBOR_HOST ..."
helm registry login \
  --username "$HARBOR_USERNAME" \
  --password "$HARBOR_TOKEN" \
  "$HARBOR_HOST"

# --- 4. 組合 Helm options ---
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

# --- 5. 判斷 Release 是否存在 ---
if helm status "$RELEASE_NAME" --namespace "$NAMESPACE" > /dev/null 2>&1; then
  echo "⬆️ Release '$RELEASE_NAME' exists in namespace '$NAMESPACE'. Upgrading..."
  helm upgrade "$RELEASE_NAME" "$CHART_PATH" "${HELM_OPTS[@]}"
else
  echo "🚀 Release '$RELEASE_NAME' does not exist. Installing..."

  if ! helm install "$RELEASE_NAME" "$CHART_PATH" "${HELM_OPTS[@]}" 2>helm-error.log; then
    # --- 6. 若安裝失敗且原因是 cert 重複，則刪除並重試 ---
    if grep -q 'certificates.cert-manager.io.*already exists' helm-error.log; then
      echo "🧨 Certificate already exists error detected. Attempting to delete conflicting certificates..."

      CERTS_TO_DELETE=$(grep 'certificates.cert-manager.io' helm-error.log | sed -nE "s/.*certificates.cert-manager.io \"([^\"]+)\" already exists/\1/p")

      for cert_name in $CERTS_TO_DELETE; do
        echo "🧹 Deleting certificate: $cert_name"
        kubectl delete certificate "$cert_name" -n "$NAMESPACE" || echo "⚠️ Failed to delete $cert_name"
      done

      echo "🔁 Retrying helm install..."
      helm install "$RELEASE_NAME" "$CHART_PATH" "${HELM_OPTS[@]}"
    else
      echo "❌ Helm install failed. See helm-error.log for details."
      cat helm-error.log
      exit 1
    fi
  fi
fi

echo "✅ Helm release '$RELEASE_NAME' installed/upgraded successfully."
