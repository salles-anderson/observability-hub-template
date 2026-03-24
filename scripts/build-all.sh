#!/bin/bash
# Build all Docker images and push to ECR
set -e

ECR_REGISTRY="${1:?Usage: ./build-all.sh ECR_REGISTRY}"
REGION="${2:-us-east-1}"

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

images=(grafana chainlit-chat mcp-aws mcp-github mcp-tfc mcp-qdrant mcp-confluence mcp-eraser)

for img in "${images[@]}"; do
  echo "=== Building $img ==="
  docker build -t $ECR_REGISTRY/$img:latest docker/$img/
  docker push $ECR_REGISTRY/$img:latest
  echo "✅ $img pushed"
done

echo "All images built and pushed!"
