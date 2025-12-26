#!/bin/bash
# ===========================================
# Kind Cluster Setup Script for Task Manager
# ===========================================
# This script sets up a Kind cluster with ArgoCD for GitOps deployment
# 
# Prerequisites:
#   - Docker installed and running
#   - kind installed (https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
#   - kubectl installed
#   - (Optional) argocd CLI for port-forwarding
#
# Usage:
#   ./setup-cluster.sh         # Deploy dev environment (default)
#   ./setup-cluster.sh dev     # Deploy dev environment
#   ./setup-cluster.sh prod    # Deploy prod environment

set -e

CLUSTER_NAME="task-manager-cluster"
ARGOCD_NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${1:-dev}"

echo "=========================================="
echo "  Task Manager - Kind Cluster Setup"
echo "  Environment: $ENVIRONMENT"
echo "=========================================="

# -------------------------------------------
# Step 1: Create Kind Cluster
# -------------------------------------------
echo ""
echo "[1/5] Creating Kind cluster..."

if kind get clusters | grep -q "$CLUSTER_NAME"; then
    echo "Cluster '$CLUSTER_NAME' already exists. Deleting..."
    kind delete cluster --name "$CLUSTER_NAME"
fi

kind create cluster --config "$PROJECT_ROOT/kind-config.yaml"

echo "✓ Kind cluster created successfully"

# -------------------------------------------
# Step 2: Install ArgoCD
# -------------------------------------------
echo ""
echo "[2/5] Installing ArgoCD..."

kubectl create namespace $ARGOCD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD using official manifests
kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n $ARGOCD_NAMESPACE

echo "✓ ArgoCD installed successfully"

# -------------------------------------------
# Step 3: Expose ArgoCD UI
# -------------------------------------------
echo ""
echo "[3/5] Configuring ArgoCD access..."

# Patch ArgoCD server to use NodePort
kubectl patch svc argocd-server -n $ARGOCD_NAMESPACE -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "targetPort": 8080, "nodePort": 30081}]}}'

# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "✓ ArgoCD UI accessible at: https://localhost:30081"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"

# -------------------------------------------
# Step 4: Create GHCR Pull Secret
# -------------------------------------------
echo ""
echo "[4/5] Creating namespaces and secrets..."

# Create task-manager namespace
kubectl create namespace task-manager --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "⚠️  IMPORTANT: Create GHCR pull secret manually:"
echo "   kubectl create secret docker-registry ghcr-secret \\"
echo "     --docker-server=ghcr.io \\"
echo "     --docker-username=AaronCallanga \\"
echo "     --docker-password=YOUR_GITHUB_PAT \\"
echo "     -n task-manager"
echo ""

# -------------------------------------------
# Step 5: Deploy ArgoCD Application
# -------------------------------------------
echo ""
echo "[5/5] Deploying ArgoCD Application ($ENVIRONMENT)..."

kubectl apply -f "$PROJECT_ROOT/argocd/application-$ENVIRONMENT.yaml"

echo "✓ ArgoCD Application deployed"

# -------------------------------------------
# Summary
# -------------------------------------------
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Access Points:"
echo "  - ArgoCD UI:     https://localhost:30081"
echo "  - Application:   http://localhost:30080/api/tasks (after deployment)"
echo ""
echo "ArgoCD Credentials:"
echo "  - Username: admin"
echo "  - Password: $ARGOCD_PASSWORD"
echo ""
echo "Next Steps:"
echo "  1. Create GHCR pull secret (see command above)"
echo "  2. Push code to GitHub to trigger CI/CD"
echo "  3. ArgoCD will automatically sync and deploy"
echo ""
echo "Useful Commands:"
echo "  - View ArgoCD apps:  kubectl get applications -n argocd"
echo "  - View pods:         kubectl get pods -n task-manager"
echo "  - View logs:         kubectl logs -f deployment/task-manager -n task-manager"
echo "  - Delete cluster:    kind delete cluster --name $CLUSTER_NAME"
echo ""
echo "To deploy a different environment:"
echo "  ./scripts/setup-cluster.sh dev   # Deploy dev environment"
echo "  ./scripts/setup-cluster.sh prod  # Deploy prod environment"
echo ""
