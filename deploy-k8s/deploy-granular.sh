#!/usr/bin/env bash
set -euo pipefail

APPS_JSON="${1:?missing APPS_JSON}"
export NAMESPACE="${2:-test}"
export ENV_NAME="${3:-NewK8s}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "--------------------------------------------------"
echo "🚀 Granular Deployment Started (OCI Version Sync)"
echo "--------------------------------------------------"
echo "Current Directory: $(pwd)" # 增加除錯資訊

for row in $(echo "${APPS_JSON}" | jq -r '.[] | @base64'); do
    _jq() { echo "${row}" | base64 -d | jq -r "${1}"; }
    APP_ID=$(_jq '.id')
    APP_VERSION=$(_jq '.version')

    # 1. 建立該 App 專屬變數
    export SERVICE_NAME="$APP_ID"
    export ROOT_DIR="." 
    
    # 2. 決定 Chart 來源 (OCI vs Local)
    if [[ -n "${CHART_REPO_BASE:-}" ]]; then
        echo "  📡 Mode: OCI Deployment"
        # ✅ 修正：直接在這裡拼接完整的 OCI Path
        export CHART_SOURCE="oci://${HARBOR_HOST}/${CHART_REPO_BASE}/${APP_ID}"
        export CHART_VERSION="${APP_VERSION}"
        
        # 登入一次即可，或在循環外登入以增進效率
        echo "$HARBOR_TOKEN" | helm registry login "$HARBOR_HOST" --username "$HARBOR_USERNAME" --password-stdin > /dev/null 2>&1
    else
        echo "  📂 Mode: Local Chart Deployment"
        export CHART_SOURCE="./charts/service"
        unset CHART_VERSION # 確保不會帶到舊的版號
    fi

    # 3. 處理 Secrets (這部分沒問題)
    bash ./scripts/deploy-secret.sh

    # 4. 處理 Image 路徑
    export REGISTRY_BASE="${HARBOR_HOST}/${IMAGE_REPO_BASE}"
    export IMAGE_REPO="${REGISTRY_BASE}/${NAMESPACE}/${APP_ID}"
    export IMAGE_TAG="$APP_VERSION"

    bash ./scripts/deploy-service.sh
    echo "✅ Finished: $APP_ID"
    echo "--------------------------------------------------"
done

echo "🎉 All deployments completed!"