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

# 1. 偵測部署類型
DEPLOY_KIND=$(grep '^kind:' "$ENV_FILE" | awk '{print $2}' | tr -d '\r')
DEPLOY_KIND="${DEPLOY_KIND:-Deployment}"

VERSION_FLAG=""
if [[ "$CHART_SOURCE" == oci://* ]] && [[ -n "${CHART_VERSION:-}" ]]; then
  VERSION_FLAG="--version $CHART_VERSION"
fi

echo "  ⚓ Running Helm Upgrade ($DEPLOY_KIND Mode)..."

# 2. 執行 Helm 部署 (加入 --atomic 與自動回滾邏輯)
# --atomic: 部署失敗時自動執行 rollback
# --cleanup-on-fail: 失敗時清理遺留的無效資源
# --history-max: 建議在 Helm 指令中或環境中設定，保持版本整潔
if ! helm upgrade --install "$SERVICE_NAME" "$CHART_SOURCE" \
  -n "$NAMESPACE" \
  -f "$ENV_FILE" \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  $VERSION_FLAG \
  --atomic \
  --cleanup-on-fail \
  --wait --timeout 5m; then
    
    echo "--------------------------------------------------"
    echo "❌ DEPLOYMENT FAILED! Started Diagnostics..."
    echo "--------------------------------------------------"
    
    # 抓取 K8s 事件 (Events) 找出失敗原因 (例如：ImagePullBackOff, CrashLoopBackOff)
    echo "🔍 Recent Kubernetes Events in $NAMESPACE:"
    kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' | tail -n 15
    
    # 如果是 Deployment，嘗試抓取 Pod 日誌 (即使已經回滾，這能幫助找出崩潰原因)
    if [[ "$DEPLOY_KIND" == "Deployment" ]]; then
      echo "📋 Fetching logs from current pods (post-rollback or failing):"
      kubectl -n "$NAMESPACE" logs deploy/"$SERVICE_NAME" --tail=50 --all-containers || echo "Could not fetch logs."
    fi
    
    echo "⚠️ Helm has automatically rolled back to the previous stable state."
    exit 1
fi

# 3. 額外狀態檢查 (針對 Job 類型)
if [[ "$DEPLOY_KIND" == "Job" ]]; then
  echo "  ⏳ Waiting for Job completion..."
  if ! kubectl -n "$NAMESPACE" wait --for=condition=complete job \
    --selector="app.kubernetes.io/name=$SERVICE_NAME" \
    --timeout=5m; then
      echo "❌ Job Failed or Timed out! Printing Pod Logs:"
      kubectl -n "$NAMESPACE" logs --selector="app.kubernetes.io/name=$SERVICE_NAME" --tail=100
      exit 1
  fi
fi

echo "✅ $SERVICE_NAME ($DEPLOY_KIND) deployed successfully!"