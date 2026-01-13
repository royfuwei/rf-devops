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

# 1. 偵測部署類型
DEPLOY_KIND=$(grep '^kind:' "$ENV_FILE" | awk '{print $2}' | tr -d '\r')
DEPLOY_KIND="${DEPLOY_KIND:-Deployment}"

VERSION_FLAG=""
if [[ "$CHART_SOURCE" == oci://* ]] && [[ -n "${CHART_VERSION:-}" ]]; then
  VERSION_FLAG="--version $CHART_VERSION"
fi

echo "  ⚓ Running Helm Upgrade ($DEPLOY_KIND Mode)..."

# 2. 執行 Helm 部署
# 使用 || 捕獲 Helm 指令失敗的情境
if ! helm upgrade --install "$SERVICE_NAME" "$CHART_SOURCE" \
  -n "$NAMESPACE" \
  -f "$ENV_FILE" \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  $VERSION_FLAG \
  --wait --timeout 5m; then
    echo "❌ Helm Upgrade Failed! Fetching recent events..."
    kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' | tail -n 10
    exit 1
fi

# 3. 狀態檢查與自動偵錯
if [[ "$DEPLOY_KIND" == "Job" ]]; then
  echo "  ⏳ Waiting for Job completion..."
  if ! kubectl -n "$NAMESPACE" wait --for=condition=complete job \
    --selector="app.kubernetes.io/name=$SERVICE_NAME" \
    --timeout=5m; then
      echo "❌ Job Failed or Timed out! Printing Pod Logs:"
      # 自動抓取該 Job 的 Pod 日誌
      kubectl -n "$NAMESPACE" logs --selector="app.kubernetes.io/name=$SERVICE_NAME" --tail=100
      exit 1
  fi
else
  echo "  ⏳ Waiting for Deployment rollout..."
  if ! kubectl -n "$NAMESPACE" rollout status deploy/"$SERVICE_NAME" --timeout=5m; then
      echo "❌ Rollout Failed! Printing Pod Logs:"
      # 自動抓取 Deployment 崩潰的日誌
      kubectl -n "$NAMESPACE" logs deploy/"$SERVICE_NAME" --tail=100 --all-containers
      exit 1
  fi
fi

echo "✅ $SERVICE_NAME ($DEPLOY_KIND) deployed successfully!"