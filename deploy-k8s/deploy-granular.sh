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

    export SERVICE_NAME="$APP_ID"
    
    # 決定 OCI 路徑與環境版號
    if [[ -n "${CHART_REPO_BASE:-}" ]]; then
        echo "  📡 Mode: OCI Deployment"
        # 對齊 Release 端的拼接邏輯
        # ✅ 拼接路徑：基礎路徑 / 環境名稱 / APP_ID
        # 例如：oci://harbor.com/royfw/rfjs/charts/k8s-royfw/api
        export CHART_SOURCE="oci://${HARBOR_HOST}/${CHART_REPO_BASE}/${ENV_NAME}/${APP_ID}"
        # ✅ 使用純淨版號
        export CHART_VERSION="${APP_VERSION}"
        
        echo "$HARBOR_TOKEN" | helm registry login "$HARBOR_HOST" --username "$HARBOR_USERNAME" --password-stdin > /dev/null 2>&1
    else
        export CHART_SOURCE="./charts/service"
        unset CHART_VERSION
    fi

    # 執行 Secret 同步
    bash ./scripts/deploy-secret.sh

    # 處理 Image 路徑 (royfw/rfjs/api)
    export REGISTRY_BASE="${HARBOR_HOST}/${IMAGE_REPO_BASE}"
    export IMAGE_REPO="${REGISTRY_BASE}/${NAMESPACE}/${APP_ID}"
    export IMAGE_TAG="$APP_VERSION"

    # 執行最終部署
    bash ./scripts/deploy-service.sh
    echo "✅ Finished: $APP_ID"
done

echo "🎉 All deployments completed!"