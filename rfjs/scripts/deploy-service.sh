#!/usr/bin/env bash
set -euo pipefail

# ===== 必填參數（由 GA / Runner 傳入） =====
: "${SERVICE_NAME:?missing SERVICE_NAME (e.g. api)}"
: "${IMAGE_REPO:?missing IMAGE_REPO (e.g. harbor.xxx/royfuwei/api)}"
: "${IMAGE_TAG:?missing IMAGE_TAG (e.g. v1.2.3 or sha-xxxx)}"

# ===== 選填（有預設） =====
: "${NAMESPACE:=rfjs}"
: "${ENV_NAME:=k8s-royfuwei}"
: "${CHART_DIR:=rfjs/charts/service}"

# ===== 環境 secrets（依 service 決定）=====
# 例如：DATABASE_URL / REDIS_URL / JWT_SECRET ...
# 不在這裡檢查是否存在，讓 helm 決定是否需要

ENV_FILE="rfjs/env/${ENV_NAME}/${SERVICE_NAME}.yaml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ values file not found: $ENV_FILE"
  exit 1
fi

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

helm upgrade --install "$SERVICE_NAME" "$CHART_DIR" \
  -n "$NAMESPACE" \
  -f "$ENV_FILE" \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  "$@" \
  --wait --timeout 5m

kubectl -n "$NAMESPACE" rollout status deploy/"$SERVICE_NAME" --timeout=5m
