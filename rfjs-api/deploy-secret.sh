#!/bin/bash

# env-secret
ENV_SECRET_NAME="env-secret"
SECRET_NAME="harbor-registry-secret"

# 尝试创建 secret
kubectl create secret docker-registry $SECRET_NAME \
  --docker-server=$DOCKER_SERVER \
  --docker-username=$DOCKER_USERNAME \
  --docker-password=$DOCKER_PASSWORD \
  --docker-email=$DOCKER_EMAIL

# check
if [ $? -ne 0 ]; then
  # failed has "already exists"
  if kubectl get secret $SECRET_NAME >/dev/null 2>&1; then
    echo "Secret '$SECRET_NAME' already exists. Deleting and recreating..."
    # delete secret
    kubectl delete secret $SECRET_NAME
    # retry create secret
    kubectl create secret docker-registry $SECRET_NAME \
      --docker-server=$DOCKER_SERVER \
      --docker-username=$DOCKER_USERNAME \
      --docker-password=$DOCKER_PASSWORD \
      --docker-email=$DOCKER_EMAIL
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

kubectl create secret generic $ENV_SECRET_NAME \
  --from-literal=DB_MONGO_URI=$DB_MONGO_URI \
  --from-literal=PUBLIC_SUPABASE_URL=$PUBLIC_SUPABASE_URL \
  --from-literal=PUBLIC_SUPABASE_ANON_KEY=$PUBLIC_SUPABASE_ANON_KEY \
  --from-literal=LINE_CHANNEL_ID=$LINE_CHANNEL_ID \
  --from-literal=LINE_CHANNEL_ACCESS_TOKEN=$LINE_CHANNEL_ACCESS_TOKEN \
  --from-literal=LINE_CHANNEL_SECRET=$LINE_CHANNEL_SECRET \
  --from-literal=LINE_NOTIFY_CLIENT_ID=$LINE_NOTIFY_CLIENT_ID \
  --from-literal=LINE_NOTIFY_CLIENT_SECRET=$LINE_NOTIFY_CLIENT_SECRET


# check
if [ $? -ne 0 ]; then
  # failed has "already exists"
  if kubectl get secret $ENV_SECRET_NAME >/dev/null 2>&1; then
    echo "Secret '$ENV_SECRET_NAME' already exists. Deleting and recreating..."
    # delete secret
    kubectl delete secret $ENV_SECRET_NAME
    # retry create secret
    kubectl create secret generic $ENV_SECRET_NAME \
      --from-literal=DB_MONGO_URI=$DB_MONGO_URI \
      --from-literal=PUBLIC_SUPABASE_URL=$PUBLIC_SUPABASE_URL \
      --from-literal=PUBLIC_SUPABASE_ANON_KEY=$PUBLIC_SUPABASE_ANON_KEY \
      --from-literal=LINE_CHANNEL_ID=$LINE_CHANNEL_ID \
      --from-literal=LINE_CHANNEL_ACCESS_TOKEN=$LINE_CHANNEL_ACCESS_TOKEN \
      --from-literal=LINE_CHANNEL_SECRET=$LINE_CHANNEL_SECRET \
      --from-literal=LINE_NOTIFY_CLIENT_ID=$LINE_NOTIFY_CLIENT_ID \
      --from-literal=LINE_NOTIFY_CLIENT_SECRET=$LINE_NOTIFY_CLIENT_SECRET
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