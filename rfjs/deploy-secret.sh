#!/bin/bash

echo "namespace: $NAMESPACE"

if [ -z "$NAMESPACE" ]; then
  echo "NAMESPACE is not set. Using default namespace."
  NAMESPACE="default"
fi

# env-secret
ENV_SECRET_NAME="env-secret"
SECRET_NAME="harbor-registry-secret"

kubectl create namespace $NAMESPACE

# 尝试创建 secret
kubectl create secret docker-registry $SECRET_NAME -n $NAMESPACE \
  --docker-server=$HARBOR_HOST \
  --docker-username=$HARBOR_USERNAME \
  --docker-password=$HARBOR_TOKEN \
  --docker-email=$HARBOR_EMAIL

# check
if [ $? -ne 0 ]; then
  # failed has "already exists"
  if kubectl get secret $SECRET_NAME -n $NAMESPACE >/dev/null 2>&1; then
    echo "Secret '$SECRET_NAME' already exists. Deleting and recreating..."
    # delete secret
    kubectl delete secret $SECRET_NAME -n $NAMESPACE
    # retry create secret
    kubectl create secret docker-registry $SECRET_NAME -n $NAMESPACE \
      --docker-server=$HARBOR_HOST \
      --docker-username=$HARBOR_USERNAME \
      --docker-password=$HARBOR_TOKEN \
      --docker-email=$HARBOR_EMAIL
    if [ $? -eq 0 ]; then
      echo "Secret '$SECRET_NAME' recreated successfully."
    else
      echo "Failed to recreate secret '$SECRET_NAME'."
    fi
  else
    echo "Failed to create secret '$SECRET_NAME'."
  fi
else
  echo "Secret '$SECRET_NAME' created successfully."
fi

kubectl create secret generic $ENV_SECRET_NAME -n $NAMESPACE \
  --from-literal=DB_MONGO_URI=$ENV_DB_MONGO_URI \
  --from-literal=PUBLIC_SUPABASE_URL=$ENV_PUBLIC_SUPABASE_URL \
  --from-literal=PUBLIC_SUPABASE_ANON_KEY=$ENV_PUBLIC_SUPABASE_ANON_KEY \
  --from-literal=LINE_CHANNEL_ID=$ENV_LINE_CHANNEL_ID \
  --from-literal=LINE_CHANNEL_ACCESS_TOKEN=$ENV_LINE_CHANNEL_ACCESS_TOKEN \
  --from-literal=LINE_CHANNEL_SECRET=$ENV_LINE_CHANNEL_SECRET \
  --from-literal=LINE_NOTIFY_CLIENT_ID=$ENV_LINE_NOTIFY_CLIENT_ID \
  --from-literal=LINE_NOTIFY_CLIENT_SECRET=$ENV_LINE_NOTIFY_CLIENT_SECRET


# check
if [ $? -ne 0 ]; then
  # failed has "already exists"
  if kubectl get secret $ENV_SECRET_NAME -n $NAMESPACE >/dev/null 2>&1; then
    echo "Secret '$ENV_SECRET_NAME' already exists. Deleting and recreating..."
    # delete secret
    kubectl delete secret $ENV_SECRET_NAME -n $NAMESPACE
    # retry create secret
    kubectl create secret generic $ENV_SECRET_NAME -n $NAMESPACE \
      --from-literal=DB_MONGO_URI=$ENV_DB_MONGO_URI \
      --from-literal=PUBLIC_SUPABASE_URL=$ENV_PUBLIC_SUPABASE_URL \
      --from-literal=PUBLIC_SUPABASE_ANON_KEY=$ENV_PUBLIC_SUPABASE_ANON_KEY \
      --from-literal=LINE_CHANNEL_ID=$ENV_LINE_CHANNEL_ID \
      --from-literal=LINE_CHANNEL_ACCESS_TOKEN=$ENV_LINE_CHANNEL_ACCESS_TOKEN \
      --from-literal=LINE_CHANNEL_SECRET=$ENV_LINE_CHANNEL_SECRET \
      --from-literal=LINE_NOTIFY_CLIENT_ID=$ENV_LINE_NOTIFY_CLIENT_ID \
      --from-literal=LINE_NOTIFY_CLIENT_SECRET=$ENV_LINE_NOTIFY_CLIENT_SECRET
    if [ $? -eq 0 ]; then
      echo "Secret '$ENV_SECRET_NAME' recreated successfully."
    else
      echo "Failed to recreate secret '$ENV_SECRET_NAME'."
    fi
  else
    echo "Failed to create secret '$ENV_SECRET_NAME'."
  fi
else
  echo "Secret '$ENV_SECRET_NAME' created successfully."
fi