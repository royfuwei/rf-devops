#!/usr/bin/env bash
set -euo pipefail

# ===== 1. 參數檢查與環境初始化 =====
# 這些變數由 deploy-granular.sh 導出
: "${SERVICE_NAME:?missing SERVICE_NAME}"
: "${CHART_SOURCE:?missing CHART_SOURCE}"
: "${PROJECT:?missing PROJECT}"
: "${NAMESPACE:?missing NAMESPACE}"
: "${ENV_NAME:?missing ENV_NAME}"

# 只有在 Local 模式下才強制需要這些，但為了穩健性建議導出
IMAGE_REPO="${IMAGE_REPO:-}"
IMAGE_TAG="${IMAGE_TAG:-}"

# 路徑定位
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# 假設路徑結構為: rf-devops/deploy-k8s/scripts/deploy-service.sh
# REPO_ROOT 會定位到 rf-devops/
DEPLOY_K8S_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$DEPLOY_K8S_ROOT")"

# 設定微調檔路徑: {PROJECT}/env/{ENV_NAME}/helm/{SERVICE_NAME}.yaml
ENV_FILE="${REPO_ROOT}/${PROJECT}/env/${ENV_NAME}/helm/${SERVICE_NAME}.yaml"

echo "--------------------------------------------------"
echo "⚓ Deploying Service: $SERVICE_NAME"
echo "   Target Namespace: $NAMESPACE"
echo "   Environment Set:  $ENV_NAME"
echo "   Chart Source:     $CHART_SOURCE"
echo "--------------------------------------------------"

# ===== 2. 自動解除 Helm 鎖定 (Pending 狀態處理) =====
# 如果先前的部署中斷導致狀態卡在 pending，自動進行處理
STATUS=$(helm status "$SERVICE_NAME" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.info.status' || echo "not-found")
if [[ "$STATUS" == "pending-"* ]]; then
  echo "⚠️ Detected pending state ($STATUS). Attempting to unlock..."
  # 嘗試回滾到上一個穩定版本，失敗則刪除重來 (慎用，但在 CI/CD 流程中通常是必要的)
  helm rollback "$SERVICE_NAME" 0 -n "$NAMESPACE" || (echo "Force unlocking by deleting..." && helm uninstall "$SERVICE_NAME" -n "$NAMESPACE")
fi

# ===== 3. 偵測部署類型與標籤規劃 =====
# 從微調檔中偵測 kind，預設為 Deployment
DEPLOY_KIND="Deployment"
if [[ -f "$ENV_FILE" ]]; then
  DEPLOY_KIND=$(grep '^kind:' "$ENV_FILE" | awk '{print $2}' | tr -d '\r' | tr -d '"' | tr -d "'")
  DEPLOY_KIND="${DEPLOY_KIND:-Deployment}"
fi

# 統一命名規範: {PROJECT}-{APP}
# 例如: rfjs-api
FULLNAME="${PROJECT}-${SERVICE_NAME}"
SELECT_LABEL="app.kubernetes.io/name=${FULLNAME}"

# ===== 4. 準備 Helm 參數數組 =====
HELM_OPTS=(
  "upgrade" "--install" "$FULLNAME" "$CHART_SOURCE"
  "-n" "$NAMESPACE"
  "--atomic"
  "--cleanup-on-fail"
  "--wait"
  "--timeout" "5m"
)

# 模式判斷與動態注入
if [[ "$CHART_SOURCE" == oci://* ]]; then
  echo "📡 Mode: OCI Deployment (Preferring internal values)"
  [[ -n "${CHART_VERSION:-}" ]] && HELM_OPTS+=("--version" "$CHART_VERSION")
  # OCI 模式下，我們不使用 --set 強制覆蓋，
  # 除非你需要在執行期動態改寫，否則維持 OCI 內的「不可變性」。
else
  echo "📂 Mode: Local Folder Deployment (Injecting dynamic values)"
  # 本地開發模式，必須手動注入當前建置的 Image 資訊
  HELM_OPTS+=("--set" "image.repository=${IMAGE_REPO}")
  HELM_OPTS+=("--set" "image.tag=${IMAGE_TAG}")
  # 確保本地模式下產出的資源名稱與 OCI 模式一致
  HELM_OPTS+=("--set" "fullnameOverride=${FULLNAME}")
  # 載入環境微調檔 (Overlays)
  if [[ -f "$ENV_FILE" ]]; then
    echo "📖 Applying overlay values from: $ENV_FILE"
    HELM_OPTS+=("-f" "$ENV_FILE")
  else
    echo "ℹ️ No specific overlay file found at $ENV_FILE, using Chart defaults."
  fi
fi

# ===== 5. 執行最終部署 =====
echo "🚀 Executing Helm Upgrade ($DEPLOY_KIND Mode)..."
if ! helm "${HELM_OPTS[@]}"; then
    echo "--------------------------------------------------"
    echo "❌ DEPLOYMENT FAILED! Started Diagnostics..."
    echo "--------------------------------------------------"
    
    # 抓取 K8s 事件輔助除錯
    echo "📋 Recent Events in $NAMESPACE:"
    kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' | tail -n 15
    
    # 抓取失敗 Pod 的日誌 (針對 Deployment)
    if [[ "$DEPLOY_KIND" == "Deployment" ]]; then
      echo "📋 Fetching logs from failing pods (Selector: $SELECT_LABEL)..."
      kubectl -n "$NAMESPACE" logs -l "$SELECT_LABEL" --tail=50 --all-containers || echo "Could not fetch logs."
    fi
    
    exit 1
fi

# ===== 6. 針對 Job 類型的額外完成檢查 =====
if [[ "$DEPLOY_KIND" == "Job" ]]; then
  echo "⏳ Waiting for Job [$FULLNAME] completion..."
  
  # 後台監控：如果 20 秒內出現 ImagePull 錯誤，立刻回報
  (
    for i in {1..10}; do
      sleep 5
      REASON=$(kubectl get pods -n "$NAMESPACE" -l "$SELECT_LABEL" -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
      if [[ "$REASON" == "ImagePullBackOff" || "$REASON" == "ErrImagePull" ]]; then
        echo "❌ ERROR: Pod is stuck in $REASON! Check registry credentials in $NAMESPACE."
        exit 1
      fi
    done
  ) &

  if ! kubectl -n "$NAMESPACE" wait --for=condition=complete job \
    --selector="$SELECT_LABEL" \
    --timeout=5m; then
      echo "❌ Job Failed or Timed out!"
      kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' | grep -i "failed" | tail -n 5
      exit 1
  fi
fi

echo "✅ $SERVICE_NAME ($DEPLOY_KIND) deployed successfully to $NAMESPACE!"