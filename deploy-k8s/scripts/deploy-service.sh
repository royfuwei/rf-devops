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

# 2. 偵測部署類型 (由 values.yaml 決定)
DEPLOY_KIND=$(grep '^kind:' "$ENV_FILE" | awk '{print $2}' | tr -d '\r')
DEPLOY_KIND="${DEPLOY_KIND:-Deployment}"

# 3. 準備 Helm 參數數組 (最穩健的執行方式)
HELM_OPTS=(
  "upgrade" "--install" "$SERVICE_NAME" "$CHART_SOURCE"
  "-n" "$NAMESPACE"
  "-f" "$ENV_FILE"
  "--atomic"
  "--cleanup-on-fail"
  "--wait"
  "--timeout" "5m"
)

# ✅ 模式判斷
if [[ "$CHART_SOURCE" == oci://* ]]; then
  echo "📡 Mode: OCI Deployment"
  if [[ -n "${CHART_VERSION:-}" ]]; then
    HELM_OPTS+=("--version" "$CHART_VERSION")
  fi
  # OCI 模式下預設不帶 --set，相信 Release 端的燒錄
else
  echo "📂 Mode: Local Folder Deployment"
  HELM_OPTS+=("--set" "image.repository=${IMAGE_REPO}")
  HELM_OPTS+=("--set" "image.tag=${IMAGE_TAG}")
fi

echo "  ⚓ Running Helm Upgrade ($DEPLOY_KIND Mode)..."

# 4. 執行 Helm 部署
# ✅ 使用 "${HELM_OPTS[@]}" 展開，完全避開 eval 與空字串問題
if ! helm "${HELM_OPTS[@]}"; then
    
    echo "--------------------------------------------------"
    echo "❌ DEPLOYMENT FAILED! Started Diagnostics..."
    echo "--------------------------------------------------"
    
    # 抓取 K8s 事件
    kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' | tail -n 15
    
    # 抓取日誌 (使用 Label Selector 避開 fullnameOverride)
    if [[ "$DEPLOY_KIND" == "Deployment" ]]; then
      echo "📋 Fetching logs from failing pods..."
      # ⚠️ 這裡的 Label 名稱必須與你的 _helpers.tpl 產出的 selectorLabels 一致
      # 根據你的 api.yaml，通常是 app.kubernetes.io/name=${SERVICE_NAME} 
      # 或是像你寫的 ${NAMESPACE}-$SERVICE_NAME
      kubectl -n "$NAMESPACE" logs -l "app.kubernetes.io/name=${SERVICE_NAME}" --tail=50 --all-containers || echo "Could not fetch logs."
    fi
    
    echo "⚠️ Helm has automatically rolled back to the previous stable state."
    exit 1
fi

# 5. 額外狀態檢查 (針對 Job 類型)
if [[ "$DEPLOY_KIND" == "Job" ]]; then
  echo "  ⏳ Waiting for Job completion..."
  if ! kubectl -n "$NAMESPACE" wait --for=condition=complete job \
    --selector="app.kubernetes.io/name=${SERVICE_NAME}" \
    --timeout=5m; then
      echo "❌ Job Failed or Timed out!"
      kubectl -n "$NAMESPACE" logs --selector="app.kubernetes.io/name=${SERVICE_NAME}" --tail=100
      exit 1
  fi
fi

echo "✅ $SERVICE_NAME ($DEPLOY_KIND) deployed successfully!"