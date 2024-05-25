#!/bin/bash

echo "Logging in to $HARBOR_HOST ..."
helm registry login \
  --username $HARBOR_USERNAME \
  --password $HARBOR_TOKEN \
  $HARBOR_HOST


RELEASE_NAME="$PROJECT_NAME"
CHART_PATH="oci://$HARBOR_HOST/$PROJECT_SOURCE/$PROJECT_NAME"

if helm status "$RELEASE_NAME" > /dev/null 2>&1; then
  echo "Release $RELEASE_NAME exists. Upgrading..."
  helm upgrade "$RELEASE_NAME" "$CHART_PATH"
else
  echo "Release $RELEASE_NAME does not exist. Installing..."
  helm install "$RELEASE_NAME" "$CHART_PATH"
fi