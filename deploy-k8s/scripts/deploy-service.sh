#!/usr/bin/env bash
set -euo pipefail

# ===== 參數檢查 =====
: "${SERVICE_NAME:?missing SERVICE_NAME}"
: "${IMAGE_REPO:?missing IMAGE_REPO}"
: "${IMAGE_TAG:?missing IMAGE_TAG}"
: "${CHART_SOURCE:?missing CHART_SOURCE}"
: "${NAMESPACE:=test}"
: "${ENV_NAME:=NewK8s}"

# 路徑定位
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEPLOY_K8S_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$DEPLOY_K8S_ROOT")"

ENV_FILE="${REPO_ROOT}/${NAMESPACE}/env/${ENV_NAME}/helm/${SERVICE_NAME}.yaml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ values file not found: $ENV_FILE"
  exit 1
fi

echo "📖 Using values from: $ENV_FILE"

# 1. 自動解除 Helm 鎖定 (Pending 狀態處理)
STATUS=$(helm status "$SERVICE_NAME" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.info.status' || echo "not-found")
if [[ "$STATUS" == "pending-upgrade" || "$STATUS" == "pending-install" || "$STATUS" == "pending-rollback" ]]; then
  echo "⚠️ Detected pending state ($STATUS). Attempting to unlock..."
  helm rollback "$SERVICE_NAME" 0 -n "$NAMESPACE" || (echo "Force unlocking by deleting..." && helm uninstall "$SERVICE_NAME" -n "$NAMESPACE")
fi

# 2. 準備 Helm 參數
DEPLOY_KIND=$(grep '^kind:' "$ENV_FILE" | awk '{print $2}' | tr -d '\r')
DEPLOY_KIND="${DEPLOY_KIND:-Deployment}"

VERSION_FLAG=""
SET_FLAGS=""

# ✅ 判斷是 OCI 還是 Local Folder
if [[ "$CHART_SOURCE" == oci://* ]]; then
  echo "📡 Mode: OCI Deployment (Using pre-baked values in Chart)"
  if [[ -n "${CHART_VERSION:-}" ]]; then
    VERSION_FLAG="--version $CHART_VERSION"
  fi
  # OCI 模式下，不使用 --set 覆蓋 image，除非你有特殊需求
  SET_FLAGS=""
else
  echo "📂 Mode: Local Folder Deployment (Injecting image metadata)"
  # Local 模式下，必須注入目前的 Image 資訊
  SET_FLAGS="--set image.repository=$IMAGE_REPO --set image.tag=$IMAGE_TAG"
fi

echo "  ⚓ Running Helm Upgrade ($DEPLOY_KIND Mode)..."

# 3. 執行 Helm 部署
# 使用 eval 來正確處理帶有空格或多個參數的變數
if ! eval "helm upgrade --install \"$SERVICE_NAME\" \"$CHART_SOURCE\" \
  -n \"$NAMESPACE\" \
  -f \"$ENV_FILE\" \
  $SET_FLAGS \
  $VERSION_FLAG \
  --atomic \
  --cleanup-on-fail \
  --wait --timeout 5m"; then
    
    echo "--------------------------------------------------"
    echo "❌ DEPLOYMENT FAILED! Started Diagnostics..."
    echo "--------------------------------------------------"
    
    kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' | tail -n 15
    
    if [[ "$DEPLOY_KIND" == "Deployment" ]]; then
      echo "📋 Fetching logs from failing pods..."
      # ✅ 修正：改用 Label Selector 抓日誌，避開 Name 拼接問題
      kubectl -n "$NAMESPACE" logs -l "app.kubernetes.io/name=${NAMESPACE}-$SERVICE_NAME" --tail=50 --all-containers || echo "Could not fetch logs."
    fi
    
    echo "⚠️ Helm has automatically rolled back to the previous stable state."
    exit 1
fi

# 4. 額外狀態檢查 (針對 Job 類型)
if [[ "$DEPLOY_KIND" == "Job" ]]; then
  echo "  ⏳ Waiting for Job completion..."
  if ! kubectl -n "$NAMESPACE" wait --for=condition=complete job \
    --selector="app.kubernetes.io/name=${NAMESPACE}-$SERVICE_NAME" \
    --timeout=5m; then
      echo "❌ Job Failed or Timed out!"
      kubectl -n "$NAMESPACE" logs --selector="app.kubernetes.io/name=${NAMESPACE}-$SERVICE_NAME" --tail=100
      exit 1
  fi
fi

echo "✅ $SERVICE_NAME ($DEPLOY_KIND) deployed successfully!"