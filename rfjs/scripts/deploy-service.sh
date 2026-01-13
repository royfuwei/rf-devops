#!/usr/bin/env bash
set -euo pipefail

: "${SERVICE_NAME:?missing SERVICE_NAME}"
: "${IMAGE_REPO:?missing IMAGE_REPO}"
: "${IMAGE_TAG:?missing IMAGE_TAG}"
: "${CHART_SOURCE:?missing CHART_SOURCE}"

ENV_FILE="rfjs/env/${ENV_NAME}/${SERVICE_NAME}.yaml"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ values file not found: $ENV_FILE"
  exit 1
fi

VERSION_FLAG=""
if [[ "$CHART_SOURCE" == oci://* ]] && [[ -n "${CHART_VERSION:-}" ]]; then
  VERSION_FLAG="--version $CHART_VERSION"
fi

helm upgrade --install "$SERVICE_NAME" "$CHART_SOURCE" \
  -n "$NAMESPACE" \
  -f "$ENV_FILE" \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  $VERSION_FLAG \
  --wait --timeout 5m

kubectl -n "$NAMESPACE" rollout status deploy/"$SERVICE_NAME" --timeout=5m