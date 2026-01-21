#!/usr/bin/env bash
set -euo pipefail

# ===== 參數檢查 =====
: "${SERVICE_NAME:?missing SERVICE_NAME}"
: "${IMAGE_REPO:?missing IMAGE_REPO}"
: "${IMAGE_TAG:?missing IMAGE_TAG}"
: "${CHART_SOURCE:?missing CHART_SOURCE}"
: "${NAMESPACE:=test}"
: "${ENV_NAME:=NewK8s}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEPLOY_K8S_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$DEPLOY_K8S_ROOT")"
ENV_FILE="${REPO_ROOT}/${NAMESPACE}/env/${ENV_NAME}/helm/${SERVICE_NAME}.yaml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ values file not found: $ENV_FILE"
  exit 1
fi

# 1. 自動解除 Helm 鎖定
STATUS=$(helm status "$SERVICE_NAME" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.info.status' || echo "not-found")
if [[ "$STATUS" == "pending-"* ]]; then
  echo "⚠️ Detected pending state ($STATUS). Attempting to unlock..."
  helm rollback "$SERVICE_NAME" 0 -n "$NAMESPACE" || helm uninstall "$SERVICE_NAME" -n "$NAMESPACE"
fi

# 2. 偵測部署類型與標籤
DEPLOY_KIND=$(grep '^kind:' "$ENV_FILE" | awk '{print $2}' | tr -d '\r')
DEPLOY_KIND="${DEPLOY_KIND:-Deployment}"
SELECT_LABEL="app.kubernetes.io/name=${NAMESPACE}-${SERVICE_NAME}"

# 3. 準備 Helm 參數
HELM_OPTS=(
  "upgrade" "--install" "$SERVICE_NAME" "$CHART_SOURCE"
  "-n" "$NAMESPACE"
  "--atomic"
  "--cleanup-on-fail"
  "--wait"
  "--timeout" "5m"
)

if [[ "$CHART_SOURCE" == oci://* ]]; then
  echo "📡 Mode: OCI Deployment"
  [[ -n "${CHART_VERSION:-}" ]] && HELM_OPTS+=("--version" "$CHART_VERSION")
else
  echo "📂 Mode: Local Folder Deployment"
  HELM_OPTS+=("-f" "$ENV_FILE")
  HELM_OPTS+=("--set" "image.repository=${IMAGE_REPO}" "--set" "image.tag=${IMAGE_TAG}")
fi

echo "  ⚓ Running Helm Upgrade ($DEPLOY_KIND Mode)..."

# 4. 執行 Helm 部署
if ! helm "${HELM_OPTS[@]}"; then
    echo "--------------------------------------------------"
    echo "❌ DEPLOYMENT FAILED! Started Diagnostics..."
    echo "--------------------------------------------------"
    kubectl get pods -n "$NAMESPACE" -l "$SELECT_LABEL" -o jsonpath='{.items[0].spec.imagePullSecrets}' || echo "No Pod found."
    kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' | tail -n 15
    exit 1
fi

# 5. 額外狀態檢查 (針對 Job 類型)
if [[ "$DEPLOY_KIND" == "Job" ]]; then
  echo "  ⏳ Waiting for Job completion (Selector: $SELECT_LABEL)..."

  # 後台監控鏡像拉取錯誤
  (
    for i in {1..12}; do
      sleep 5
      REASON=$(kubectl get pods -n "$NAMESPACE" -l "$SELECT_LABEL" -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
      if [[ "$REASON" == "ImagePullBackOff" || "$REASON" == "ErrImagePull" ]]; then
        echo "❌ ERROR: Pod is stuck in $REASON!"
        exit 1
      fi
    done
  ) &

  if ! kubectl -n "$NAMESPACE" wait --for=condition=complete job --selector="$SELECT_LABEL" --timeout=5m; then
      echo "❌ Job Failed or Timed out!"
      kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' | grep -i "failed" | tail -n 5
      exit 1
  fi
  echo "✅ Job completed successfully."
fi

echo "✅ $SERVICE_NAME ($DEPLOY_KIND) deployed successfully!"