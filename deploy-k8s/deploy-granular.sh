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

    echo "📦 App: $APP_ID (v$APP_VERSION)"

    # 1. Secrets
    export SERVICE_NAME="$APP_ID"
    export ROOT_DIR="." 
    # 確保這裡的路徑在當前目錄下能找到
    bash ./scripts/deploy-secret.sh

    # 2. OCI vs Local 邏輯
    if [[ -n "${CHART_OCI_REPO:-}" ]]; then
        echo "  📡 Mode: OCI Deployment"
        export CHART_SOURCE="$CHART_OCI_REPO"
        export CHART_VERSION="${APP_VERSION}" # 動態更新 OCI Value
        echo "$HARBOR_TOKEN" | helm registry login "$HARBOR_HOST" --username "$HARBOR_USERNAME" --password-stdin > /dev/null 2>&1
    else
        echo "  📂 Mode: Local Chart Deployment"
        export CHART_SOURCE="./charts/service"
    fi

    # 3. Image
    export REGISTRY_BASE="${HARBOR_HOST}/${HARBOR_PROJECT}"
    export IMAGE_REPO="${REGISTRY_BASE}/${APP_ID}"
    export IMAGE_TAG="$APP_VERSION"

    bash ./scripts/deploy-service.sh
    echo "✅ Finished: $APP_ID"
    echo "--------------------------------------------------"
done

echo "🎉 All deployments completed!"