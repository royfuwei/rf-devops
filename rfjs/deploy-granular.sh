#!/usr/bin/env bash
set -euo pipefail

# 參數接收
APPS_JSON="${1:?missing APPS_JSON}"
export NAMESPACE="${2:-rfjs}"
export ENV_NAME="${3:-k8s-royfuwei}"

# 取得 rf-devops 的根目錄路徑
# 假設此腳本路徑為 rf-devops/rfjs/deploy-granular.sh
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEV_OPS_ROOT="$(dirname "$SCRIPT_DIR")"

echo "--------------------------------------------------"
echo "🚀 Granular Deployment Started"
echo "📂 Root: $DEV_OPS_ROOT"
echo "--------------------------------------------------"

# 進入根目錄，確保後續 ./rfjs/scripts/ 的相對路徑有效
cd "$DEV_OPS_ROOT"

for row in $(echo "${APPS_JSON}" | jq -r '.[] | @base64'); do
    _jq() {
     echo "${row}" | base64 --decode | jq -r "${1}"
    }

    APP_ID=$(_jq '.id')
    APP_VERSION=$(_jq '.version')

    echo "📦 App: $APP_ID (v$APP_VERSION)"

    # 設定 deploy-secret.sh 參數
    export SERVICE_NAME="$APP_ID"
    export ROOT_DIR="." 

    echo "  🔐 Applying Secrets..."
    bash ./rfjs/scripts/deploy-secret.sh

    # 設定 deploy-service.sh 參數
    # 注意：這裡的 IMAGE_REPO 要跟 Harbor 上的路徑完全一致
    export IMAGE_REPO="${HARBOR_HOST}/royfuwei/rfjs-${APP_ID}"
    export IMAGE_TAG="$APP_VERSION"
    export CHART_DIR="rfjs/charts/service"

    echo "  ⚓ Running Helm Upgrade..."
    # 執行部署腳本
    bash ./rfjs/scripts/deploy-service.sh

    echo "✅ Finished: $APP_ID"
    echo "--------------------------------------------------"
done

echo "🎉 All deployments completed!"