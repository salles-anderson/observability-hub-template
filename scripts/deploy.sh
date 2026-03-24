#!/bin/bash
# Force new deployment on ECS services
set -e

CLUSTER="${1:?Usage: ./deploy.sh CLUSTER [SERVICE]}"
SERVICE="${2:-all}"

if [ "$SERVICE" = "all" ]; then
  for svc in $(aws ecs list-services --cluster $CLUSTER --query 'serviceArns[*]' --output text | tr '\t' '\n' | awk -F'/' '{print $NF}'); do
    echo "Deploying $svc..."
    aws ecs update-service --cluster $CLUSTER --service $svc --force-new-deployment --query 'service.status' --output text
  done
else
  aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment --query 'service.status' --output text
fi
