#!/bin/bash

# env-secret
ENV_SECRET_NAME="env-secret"
SECRET_NAME="harbor-registry-secret"

# secret
kubectl create secret docker-registry $SECRET_NAME \
  --docker-server=$HARBOR_HOST \
  --docker-username=$HARBOR_USERNAME \
  --docker-password=$HARBOR_TOKEN \
  --docker-email=$HARBOR_EMAIL

# check
if [ $? -ne 0 ]; then
  # failed has "already exists"
  if kubectl get secret $SECRET_NAME >/dev/null 2>&1; then
    echo "Secret '$SECRET_NAME' already exists. Deleting and recreating..."
    # delete secret
    kubectl delete secret $SECRET_NAME
    # retry create secret
    kubectl create secret docker-registry $SECRET_NAME \
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

kubectl create secret generic $ENV_SECRET_NAME \
  --from-literal=DB_MONGO_URI=$ENV_DB_MONGO_URI \
  --from-literal=PUBLIC_SUPABASE_URL=$ENV_PUBLIC_SUPABASE_URL \
  --from-literal=PUBLIC_SUPABASE_ANON_KEY=$ENV_PUBLIC_SUPABASE_ANON_KEY \
  --from-literal=JWT_SECRET=$ENV_JWT_SECRET \
  --from-literal=JWT_EXPIRES_IN=$ENV_JWT_EXPIRES_IN


# check
if [ $? -ne 0 ]; then
  # failed has "already exists"
  if kubectl get secret $ENV_SECRET_NAME >/dev/null 2>&1; then
    echo "Secret '$ENV_SECRET_NAME' already exists. Deleting and recreating..."
    # delete secret
    kubectl delete secret $ENV_SECRET_NAME
    # retry create secret
    kubectl create secret generic $ENV_SECRET_NAME \
      --from-literal=DB_MONGO_URI=$ENV_DB_MONGO_URI \
      --from-literal=PUBLIC_SUPABASE_URL=$ENV_PUBLIC_SUPABASE_URL \
      --from-literal=PUBLIC_SUPABASE_ANON_KEY=$ENV_PUBLIC_SUPABASE_ANON_KEY \
      --from-literal=JWT_SECRET=$ENV_JWT_SECRET \
      --from-literal=JWT_EXPIRES_IN=$ENV_JWT_EXPIRES_IN
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