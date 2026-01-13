#!/usr/bin/env bash
set -euo pipefail

# ===== 參數檢查 =====
: "${SERVICE_NAME:?missing SERVICE_NAME}"
: "${IMAGE_REPO:?missing IMAGE_REPO}"
: "${IMAGE_TAG:?missing IMAGE_TAG}"
: "${CHART_SOURCE:?missing CHART_SOURCE}"
: "${NAMESPACE:=rfjs}"
: "${ENV_NAME:=k8s-royfuwei}"

ENV_FILE="rfjs/env/${ENV_NAME}/${SERVICE_NAME}.yaml"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ values file not found: $ENV_FILE"
  exit 1
fi

# 1. 偵測部署類型 (從 yaml 中抓取 kind，預設為 Deployment)
# 使用 grep + awk 簡單解析，避免依賴 yq
DEPLOY_KIND=$(grep '^kind:' "$ENV_FILE" | awk '{print $2}' | tr -d '\r')
DEPLOY_KIND="${DEPLOY_KIND:-Deployment}"

VERSION_FLAG=""
if [[ "$CHART_SOURCE" == oci://* ]] && [[ -n "${CHART_VERSION:-}" ]]; then
  VERSION_FLAG="--version $CHART_VERSION"
fi

echo "  ⚓ Running Helm Upgrade ($DEPLOY_KIND Mode)..."

# 2. 執行 Helm 部署
helm upgrade --install "$SERVICE_NAME" "$CHART_SOURCE" \
  -n "$NAMESPACE" \
  -f "$ENV_FILE" \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  $VERSION_FLAG \
  --wait --timeout 5m

# 3. 根據類型執行不同的狀態檢查邏輯
if [[ "$DEPLOY_KIND" == "Job" ]]; then
  echo "  ⏳ Waiting for Job to complete..."
  # 注意：因為 Job 名稱帶有 Revision，我們使用 Label Selector 來追蹤
  # 或是直接檢查該 Release 是否有成功的 Job
  kubectl -n "$NAMESPACE" wait --for=condition=complete job \
    --selector="app.kubernetes.io/name=$SERVICE_NAME" \
    --timeout=5m
else
  echo "  ⏳ Waiting for Deployment rollout..."
  kubectl -n "$NAMESPACE" rollout status deploy/"$SERVICE_NAME" --timeout=5m
fi

echo "✅ $SERVICE_NAME ($DEPLOY_KIND) deployment finished successfully!"