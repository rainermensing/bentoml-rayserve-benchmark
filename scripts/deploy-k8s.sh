#!/bin/bash
# Deploy resources to Kind Kubernetes cluster(s)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

SERVICE=${1:-"all"}
REPLICAS=${2:-1}

cd "$PROJECT_DIR"

deploy_service() {
    local svc=$1
    echo "=========================================="
    echo "Deploying $svc to its own cluster"
    echo "=========================================="
    "$SCRIPT_DIR/manage-service-cluster.sh" up "$svc" "$REPLICAS"
}

if [ "$SERVICE" == "all" ]; then
    deploy_service "bentoml"
    deploy_service "fastapi"
    deploy_service "rayserve"
else
    deploy_service "$SERVICE"
fi

echo ""
echo "=========================================="
echo "Deployment Complete"
echo "=========================================="
