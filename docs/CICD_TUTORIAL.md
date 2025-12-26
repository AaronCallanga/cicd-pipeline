# Complete CI/CD Pipeline Tutorial

A comprehensive step-by-step guide to setting up a production-grade CI/CD pipeline using GitHub Actions, Kubernetes (Kind), and ArgoCD GitOps.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites Installation](#2-prerequisites-installation)
3. [Understanding the Architecture](#3-understanding-the-architecture)
4. [Setting Up the GitHub Repository](#4-setting-up-the-github-repository)
5. [Creating a Kind Kubernetes Cluster](#5-creating-a-kind-kubernetes-cluster)
6. [Installing and Configuring ArgoCD](#6-installing-and-configuring-argocd)
7. [Configuring GitHub Container Registry (GHCR)](#7-configuring-github-container-registry-ghcr)
8. [Deploying the Application](#8-deploying-the-application)
9. [Testing the CI/CD Pipeline](#9-testing-the-cicd-pipeline)
10. [Troubleshooting](#10-troubleshooting)
11. [Cleanup](#11-cleanup)

---

## 1. Introduction

### What You'll Learn

By the end of this tutorial, you will understand:

- **Kubernetes basics** with Kind (Kubernetes in Docker)
- **GitOps principles** using ArgoCD
- **CI/CD pipelines** with GitHub Actions
- **Container registries** with GitHub Container Registry (GHCR)
- **Infrastructure as Code** with Kustomize and environment overlays

### What We're Building

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CI/CD Pipeline Flow                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Developer          GitHub Actions              ArgoCD         Kubernetes  │
│   ─────────          ──────────────              ──────         ──────────  │
│                                                                             │
│   git push  ───────►  Build & Test                                          │
│                           │                                                 │
│                           ▼                                                 │
│                      CodeQL Scan                                            │
│                           │                                                 │
│                           ▼                                                 │
│                    Build Container ─────► Push to GHCR                      │
│                           │                                                 │
│                           ▼                                                 │
│                   Update K8s Manifest                                       │
│                           │                                                 │
│                           └─────────────► Detect Change ───► Deploy to K8s  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Prerequisites Installation

### 2.1 Install Docker Desktop

Docker is required to run Kind (Kubernetes in Docker).

**Windows:**
1. Download Docker Desktop from https://www.docker.com/products/docker-desktop/
2. Run the installer
3. Restart your computer when prompted
4. Start Docker Desktop and wait for it to be ready (green icon in system tray)

**Verify installation:**
```powershell
docker --version
# Expected output: Docker version 24.x.x or higher
```

### 2.2 Install Kind

Kind (Kubernetes in Docker) allows you to run Kubernetes clusters locally using Docker containers.

**Windows (PowerShell as Administrator):**
```powershell
# Option 1: Using Chocolatey
choco install kind

# Option 2: Using winget
winget install Kubernetes.kind

# Option 3: Manual download
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
Move-Item .\kind-windows-amd64.exe C:\Windows\System32\kind.exe
```

**Verify installation:**
```powershell
kind --version
# Expected output: kind version 0.20.0 or higher
```

### 2.3 Install kubectl

kubectl is the Kubernetes command-line tool.

**Windows (PowerShell as Administrator):**
```powershell
# Option 1: Using Chocolatey
choco install kubernetes-cli

# Option 2: Using winget
winget install Kubernetes.kubectl

# Option 3: Manual download
curl.exe -LO "https://dl.k8s.io/release/v1.29.0/bin/windows/amd64/kubectl.exe"
Move-Item .\kubectl.exe C:\Windows\System32\kubectl.exe
```

**Verify installation:**
```powershell
kubectl version --client
# Expected output: Client Version: v1.29.0 or higher
```

---

## 3. Understanding the Architecture

### 3.1 Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **GitHub Actions** | CI/CD automation | `.github/workflows/` |
| **Kind** | Local Kubernetes cluster | Docker containers |
| **ArgoCD** | GitOps deployment | Kubernetes cluster |
| **GHCR** | Container image registry | GitHub |
| **Kustomize** | K8s manifest management | `kustomize/` |

### 3.2 Directory Structure

```
task-manager/
├── .github/
│   └── workflows/
│       └── ci.yml                    # CI/CD pipeline definition
├── argocd/
│   ├── application-dev.yaml          # Dev environment ArgoCD App
│   └── application-prod.yaml         # Prod environment ArgoCD App
├── kustomize/
│   ├── base/
│   │   ├── kustomization.yaml        # Base Kustomize config
│   │   ├── namespace.yaml            # Kubernetes namespace
│   │   ├── app-deployment.yaml       # App Deployment + Service
│   │   ├── postgres.yaml             # PostgreSQL + Service + PVC
│   │   └── config.yaml               # ConfigMap + Secrets
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml    # Dev overlay config
│       │   └── patches.yaml          # Dev-specific patches
│       └── prod/
│           ├── kustomization.yaml    # Prod overlay config
│           └── patches.yaml          # Prod-specific patches
├── scripts/
│   ├── setup-cluster.ps1             # Windows setup script
│   └── setup-cluster.sh              # Linux/Mac setup script
├── src/                              # Application source code
├── Dockerfile                        # Container image definition
├── kind-config.yaml                  # Kind cluster configuration
└── pom.xml                           # Maven build configuration
```

### 3.3 Environment Differences

| Setting | Dev | Prod |
|---------|-----|------|
| App Replicas | 1 | 3 |
| PostgreSQL Replicas | 1 | 1 |
| App Memory | 256Mi-512Mi | 512Mi-1Gi |
| App CPU | 100m-250m | 250m-1000m |
| PVC Storage | 1Gi | 10Gi |
| SQL Logging | Enabled | Disabled |

---

## 4. Setting Up the GitHub Repository

### 4.1 Create a GitHub Repository

1. Go to https://github.com/new
2. Create a new repository named `task-manager` (or your preferred name)
3. Keep it **public** (for free GHCR access) or **private**
4. Don't initialize with README (we already have one)

### 4.2 Configure Repository Secrets

For the CI/CD pipeline to push to GHCR, you need to configure permissions:

1. Go to your repository → **Settings** → **Actions** → **General**
2. Scroll to **Workflow permissions**
3. Select **Read and write permissions**
4. Check **Allow GitHub Actions to create and approve pull requests**
5. Click **Save**

### 4.3 Push Code to GitHub

```powershell
# Navigate to project directory
cd c:\Users\MY PC\Desktop\task-manager

# Initialize git (if not already)
git init

# Add remote origin
git remote add origin https://github.com/AaronCallanga/task-manager.git

# Add all files
git add .

# Commit
git commit -m "feat: initial CI/CD pipeline setup"

# Push to main branch
git push -u origin main
```

---

## 5. Creating a Kind Kubernetes Cluster

### 5.1 Understanding kind-config.yaml

Our Kind configuration file (`kind-config.yaml`) defines the cluster:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: task-manager-cluster

nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080  # Application
        hostPort: 30080
      - containerPort: 30081  # ArgoCD UI
        hostPort: 30081
```

### 5.2 Create the Cluster Using Setup Script

**Windows (PowerShell):**
```powershell
# Deploy dev environment (default)
.\scripts\setup-cluster.ps1

# Or deploy prod environment
.\scripts\setup-cluster.ps1 prod
```

**Linux/Mac:**
```bash
chmod +x scripts/setup-cluster.sh

# Deploy dev environment (default)
./scripts/setup-cluster.sh

# Or deploy prod environment
./scripts/setup-cluster.sh prod
```

### 5.3 Manual Cluster Creation

```powershell
# Create Kind cluster
kind create cluster --config kind-config.yaml

# Verify cluster
kind get clusters
kubectl get nodes
```

---

## 6. Installing and Configuring ArgoCD

### 6.1 What is ArgoCD?

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. It:
- Monitors your Git repository for changes
- Compares the desired state (Git) with the actual state (cluster)
- Automatically syncs when differences are detected

### 6.2 Install ArgoCD (if not using setup script)

```powershell
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Expose ArgoCD UI
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "targetPort": 8080, "nodePort": 30081}]}}'

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

### 6.3 Access ArgoCD UI

1. Open your browser and go to: **https://localhost:30081**
2. Accept the security warning (self-signed certificate)
3. Login with:
   - Username: `admin`
   - Password: (from the previous step)

---

## 7. Configuring GitHub Container Registry (GHCR)

### 7.1 Create a Personal Access Token (PAT)

1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Select scopes: `read:packages`, `write:packages`, `delete:packages`
4. Click **Generate token** and copy it

### 7.2 Create Kubernetes Pull Secret

```powershell
kubectl create namespace task-manager

kubectl create secret docker-registry ghcr-secret `
  --docker-server=ghcr.io `
  --docker-username=AaronCallanga `
  --docker-password=YOUR_GITHUB_PAT `
  -n task-manager
```

---

## 8. Deploying the Application

### 8.1 Deploy ArgoCD Application

**Dev environment:**
```powershell
kubectl apply -f argocd/application-dev.yaml
```

**Prod environment:**
```powershell
kubectl apply -f argocd/application-prod.yaml
```

### 8.2 Understanding the ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-manager-dev
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/AaronCallanga/task-manager.git
    targetRevision: HEAD           # Always track latest commit
    path: kustomize/overlays/dev   # Environment-specific path
  destination:
    server: https://kubernetes.default.svc
    namespace: task-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 8.3 Verify Deployment

```powershell
# Check ArgoCD application status
kubectl get applications -n argocd

# Check pods
kubectl get pods -n task-manager

# Test the API
Invoke-RestMethod -Uri "http://localhost:30080/api/tasks" -Method Get
```

---

## 9. Testing the CI/CD Pipeline

### 9.1 Trigger the Pipeline

```powershell
# Make a small change
Add-Content -Path README.md -Value "`n<!-- Trigger CI/CD $(Get-Date) -->"

# Commit and push
git add .
git commit -m "test: trigger CI/CD pipeline"
git push
```

### 9.2 Monitor the Pipeline

1. Go to your GitHub repository
2. Click on **Actions** tab
3. Watch the workflow run

### 9.3 Verify Deployment

After the pipeline completes:

```powershell
# Check pods
kubectl get pods -n task-manager

# View logs
kubectl logs -f deployment/task-manager -n task-manager

# Test API
Invoke-RestMethod -Uri "http://localhost:30080/api/tasks" -Method Get
```

---

## 10. Troubleshooting

### Common Issues

**Pod stuck in `ImagePullBackOff`:**
```powershell
kubectl describe pod -n task-manager -l app=task-manager
# Check if GHCR secret is correct
```

**ArgoCD shows `OutOfSync`:**
```powershell
kubectl patch application task-manager-dev -n argocd --type merge -p '{"metadata": {"annotations": {"argocd.argoproj.io/refresh": "hard"}}}'
```

**CI/CD fails at container push:**
- Check GitHub Actions workflow permissions
- Go to Settings → Actions → General → Workflow permissions

### Useful Debug Commands

```powershell
# View pod logs
kubectl logs -f deployment/task-manager -n task-manager

# View pod events
kubectl describe pod -n task-manager -l app=task-manager

# View ArgoCD logs
kubectl logs -f deployment/argocd-server -n argocd

# Preview kustomize output
kubectl kustomize kustomize/overlays/dev
kubectl kustomize kustomize/overlays/prod
```

---

## 11. Cleanup

```powershell
# Delete the Kind cluster
kind delete cluster --name task-manager-cluster

# Verify deletion
kind get clusters

# Remove Docker resources (optional)
docker system prune -a
```

---

## Quick Reference

| Resource | URL |
|----------|-----|
| Application API | http://localhost:30080/api/tasks |
| ArgoCD UI | https://localhost:30081 |
| GitHub Actions | https://github.com/AaronCallanga/task-manager/actions |
| GHCR Packages | https://github.com/AaronCallanga?tab=packages |

| Command | Purpose |
|---------|---------|
| `kind get clusters` | List Kind clusters |
| `kubectl get pods -n task-manager` | List application pods |
| `kubectl get applications -n argocd` | List ArgoCD applications |
| `kubectl kustomize kustomize/overlays/dev` | Preview dev manifests |
| `kind delete cluster --name task-manager-cluster` | Delete cluster |
