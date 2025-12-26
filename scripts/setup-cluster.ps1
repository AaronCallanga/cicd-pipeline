# ===========================================
# Kind Cluster Setup Script for Task Manager (PowerShell)
# ===========================================
# This script sets up a Kind cluster with ArgoCD for GitOps deployment
#
# Prerequisites:
#   - Docker Desktop installed and running
#   - kind installed (winget install Kubernetes.kind)
#   - kubectl installed (winget install Kubernetes.kubectl)

$ErrorActionPreference = "Stop"

$CLUSTER_NAME = "task-manager-cluster"
$ARGOCD_NAMESPACE = "argocd"
$PROJECT_ROOT = Split-Path -Parent $PSScriptRoot
$ENVIRONMENT = if ($args[0]) { $args[0] } else { "dev" }

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Task Manager - Kind Cluster Setup" -ForegroundColor Cyan
Write-Host "  Environment: $ENVIRONMENT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# -------------------------------------------
# Step 1: Create Kind Cluster
# -------------------------------------------
Write-Host "`n[1/5] Creating Kind cluster..." -ForegroundColor Yellow

$existingClusters = kind get clusters 2>$null
if ($existingClusters -contains $CLUSTER_NAME) {
    Write-Host "Cluster '$CLUSTER_NAME' already exists. Deleting..." -ForegroundColor Yellow
    kind delete cluster --name $CLUSTER_NAME
}

kind create cluster --config "$PROJECT_ROOT\kind-config.yaml"

Write-Host "✓ Kind cluster created successfully" -ForegroundColor Green

# -------------------------------------------
# Step 2: Install ArgoCD
# -------------------------------------------
Write-Host "`n[2/5] Installing ArgoCD..." -ForegroundColor Yellow

kubectl create namespace $ARGOCD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD using official manifests
kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

Write-Host "Waiting for ArgoCD to be ready (this may take a few minutes)..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n $ARGOCD_NAMESPACE

Write-Host "✓ ArgoCD installed successfully" -ForegroundColor Green

# -------------------------------------------
# Step 3: Expose ArgoCD UI
# -------------------------------------------
Write-Host "`n[3/5] Configuring ArgoCD access..." -ForegroundColor Yellow

# Patch ArgoCD server to use NodePort
kubectl patch svc argocd-server -n $ARGOCD_NAMESPACE -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "targetPort": 8080, "nodePort": 30081}]}}'

# Get initial admin password
$ARGOCD_PASSWORD = kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
$ARGOCD_PASSWORD = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ARGOCD_PASSWORD))

Write-Host "✓ ArgoCD UI accessible at: https://localhost:30081" -ForegroundColor Green
Write-Host "  Username: admin"
Write-Host "  Password: $ARGOCD_PASSWORD"

# -------------------------------------------
# Step 4: Create Namespaces
# -------------------------------------------
Write-Host "`n[4/5] Creating namespaces..." -ForegroundColor Yellow

kubectl create namespace task-manager --dry-run=client -o yaml | kubectl apply -f -

Write-Host ""
Write-Host "⚠️  IMPORTANT: Create GHCR pull secret manually:" -ForegroundColor Yellow
Write-Host '   kubectl create secret docker-registry ghcr-secret `' -ForegroundColor White
Write-Host '     --docker-server=ghcr.io `' -ForegroundColor White
Write-Host '     --docker-username=AaronCallanga `' -ForegroundColor White
Write-Host '     --docker-password=YOUR_GITHUB_PAT `' -ForegroundColor White
Write-Host '     -n task-manager' -ForegroundColor White
Write-Host ""

# -------------------------------------------
# Step 5: Deploy ArgoCD Application
# -------------------------------------------
Write-Host "`n[5/5] Deploying ArgoCD Application ($ENVIRONMENT)..." -ForegroundColor Yellow

kubectl apply -f "$PROJECT_ROOT\argocd\application-$ENVIRONMENT.yaml"

Write-Host "✓ ArgoCD Application deployed" -ForegroundColor Green

# -------------------------------------------
# Summary
# -------------------------------------------
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Access Points:" -ForegroundColor White
Write-Host "  - ArgoCD UI:     https://localhost:30081"
Write-Host "  - Application:   http://localhost:30080/api/tasks (after deployment)"
Write-Host ""
Write-Host "ArgoCD Credentials:" -ForegroundColor White
Write-Host "  - Username: admin"
Write-Host "  - Password: $ARGOCD_PASSWORD"
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor White
Write-Host "  1. Create GHCR pull secret (see command above)"
Write-Host "  2. Push code to GitHub to trigger CI/CD"
Write-Host "  3. ArgoCD will automatically sync and deploy"
Write-Host ""
Write-Host "Useful Commands:" -ForegroundColor White
Write-Host "  - View ArgoCD apps:  kubectl get applications -n argocd"
Write-Host "  - View pods:         kubectl get pods -n task-manager"
Write-Host "  - View logs:         kubectl logs -f deployment/task-manager -n task-manager"
Write-Host "  - Delete cluster:    kind delete cluster --name $CLUSTER_NAME"
Write-Host ""
Write-Host "To deploy a different environment:" -ForegroundColor White
Write-Host "  .\scripts\setup-cluster.ps1 dev   # Deploy dev environment"
Write-Host "  .\scripts\setup-cluster.ps1 prod  # Deploy prod environment"
Write-Host ""
