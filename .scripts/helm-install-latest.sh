#!/bin/bash

echo "namespace: $NAMESPACE"

if [ -z "$NAMESPACE" ]; then
  echo "NAMESPACE is not set. Using default namespace."
  NAMESPACE="default"
fi

RELEASE_NAME="$PROJECT_NAME"
CHART_PATH="oci://$HARBOR_HOST/$PROJECT_SOURCE/$PROJECT_NAME"

echo "Logging in to $HARBOR_HOST ..."
helm registry login \
  --username $HARBOR_USERNAME \
  --password $HARBOR_TOKEN \
  --namespace $NAMESPACE \
  --create-namespace \
  $HARBOR_HOST

if helm status "$RELEASE_NAME" > /dev/null 2>&1; then
  echo "Release $RELEASE_NAME exists. Upgrading..."
  helm upgrade "$RELEASE_NAME" "$CHART_PATH --namespace $NAMESPACE --create-namespace"
else
  echo "Release $RELEASE_NAME does not exist. Installing..."
  helm install "$RELEASE_NAME" "$CHART_PATH --namespace $NAMESPACE --create-namespace"
fi