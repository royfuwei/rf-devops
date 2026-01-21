#!/usr/bin/env bash
set -euo pipefail

# ===== 1. 參數解析 =====
# 參數 1: 來自 detect job 的 JSON 矩陣
APPS_JSON="${1:?missing APPS_JSON}"
# 參數 2: 產品專案名稱 (決定目錄路徑與 Harbor 專案層級)
export PROJECT="${2:-rfjs}"
# 參數 3: K8s 實際部署空間 (建議格式: {project}-{stage})
export NAMESPACE="${3:-rfjs-dev}"
# 參數 4: 環境設定集名稱 (決定讀取哪份 YAML 與 OCI 路徑)
export ENV_NAME="${4:-royfw-dev}"

# 取得腳本所在目錄的絕對路徑，確保後續呼叫 scripts/*.sh 不會出錯
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# 定義 DevOps 倉庫根目錄
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "🚀 Granular Deployment Dispatcher"
echo "   Project:   $PROJECT"
echo "   Namespace: $NAMESPACE"
echo "   Env Set:   $ENV_NAME"
echo "=================================================="

# ===== 2. 遍歷 Apps 矩陣執行部署 =====
for row in $(echo "${APPS_JSON}" | jq -r '.[] | @base64'); do
    _jq() { echo "${row}" | base64 -d | jq -r "${1}"; }
    
    APP_ID=$(_jq '.id')
    APP_VERSION=$(_jq '.version')
    export SERVICE_NAME="$APP_ID"

    echo "📦 Processing Application: $APP_ID ($APP_VERSION)"

    # --- Step A: 準備 Secret ---
    # 傳遞環境變數給子腳本，它會自動從 {PROJECT}/env/{ENV_NAME}/env_keys 讀取
    bash "${SCRIPT_DIR}/scripts/deploy-secret.sh"

    # --- Step B: 決定 Chart 來源模式 ---
    if [[ -n "${CHART_REPO_BASE:-}" ]]; then
        echo "   📡 Mode: OCI Deployment"
        # 邏輯：oci://{HOST}/{BASE}/{ENV_NAME}/{APP_ID}
        # 這種寫法讓你可以把針對 prod 預包裝好的 Chart 部署到 dev namespace
        export CHART_SOURCE="oci://${HARBOR_HOST}/${CHART_REPO_BASE}/${ENV_NAME}/${APP_ID}"
        export CHART_VERSION="${APP_VERSION}"
        
        # 登入 Helm Registry (確保有權限拉取)
        echo "$HARBOR_TOKEN" | helm registry login "$HARBOR_HOST" --username "$HARBOR_USERNAME" --password-stdin > /dev/null 2>&1
    else
        echo "   📂 Mode: Local Folder Deployment"
        # 回退到倉庫內的通用模板路徑
        export CHART_SOURCE="${REPO_ROOT}/deploy-k8s/charts/service"
        unset CHART_VERSION
    fi

    # --- Step C: 定義 Image 路徑 (供 Local 模式或除錯使用) ---
    # 格式：{HOST}/{BASE}/{PROJECT}/{APP_ID}
    export REGISTRY_BASE="${HARBOR_HOST}/${IMAGE_REPO_BASE}"
    export IMAGE_REPO="${REGISTRY_BASE}/${PROJECT}/${APP_ID}"
    export IMAGE_TAG="$APP_VERSION"

    # --- Step D: 呼叫 Service 部署腳本 ---
    # 此腳本會處理最終的 helm upgrade 指令
    if ! bash "${SCRIPT_DIR}/scripts/deploy-service.sh"; then
        echo "❌ Deployment failed for $APP_ID"
        exit 1
    fi

    echo "✅ Successfully deployed $APP_ID"
    echo "--------------------------------------------------"
done

echo "🎉 All applications in $PROJECT have been processed for $NAMESPACE!"