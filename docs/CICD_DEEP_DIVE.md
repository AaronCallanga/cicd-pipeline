# CI/CD Pipeline Deep Dive

A comprehensive technical explanation of the entire CI/CD pipeline, from code push to production deployment.

---

## Pipeline Overview

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                              CI/CD PIPELINE FLOW                                      │
├──────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│   ┌─────────┐    ┌─────────────────────────────────────────────────────────────┐    │
│   │  DEV    │    │                  GITHUB ACTIONS (CI)                        │    │
│   │         │    │  ┌───────┐  ┌──────┐  ┌────────┐  ┌───────┐  ┌──────────┐  │    │
│   │ git     │───►│  │ Build │─►│ Test │─►│ CodeQL │─►│ Docker│─►│ Update   │  │    │
│   │ push    │    │  └───────┘  └──────┘  └────────┘  └───────┘  │ Manifest │  │    │
│   └─────────┘    │                                              └──────────┘  │    │
│                  └──────────────────────────────────────────────────┬─────────┘    │
│                                                                     │              │
│   ┌─────────────────────────────────────────────────────────────────▼──────────┐   │
│   │                            GITOPS (CD)                                      │   │
│   │  ┌────────────────┐         ┌────────────────┐         ┌────────────────┐  │   │
│   │  │  GitHub Repo   │ ◄─────► │    ArgoCD      │ ───────►│  Kubernetes    │  │   │
│   │  │ (Single Source │         │  (Watches Git) │         │  (Kind Cluster)│  │   │
│   │  │   of Truth)    │         └────────────────┘         └────────────────┘  │   │
│   │  └────────────────┘                                                         │   │
│   └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Continuous Integration (CI)

### Stage 1: Trigger

The pipeline is triggered when code is pushed to `main` or `master` branches, or when a pull request is opened.

```yaml
# .github/workflows/ci.yml
on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
```

**How it works:**
1. Developer pushes code to GitHub
2. GitHub detects the push event
3. GitHub Actions runner is provisioned (Ubuntu VM)
4. The workflow YAML is parsed and jobs are scheduled

---

### Stage 2: Build

The application is compiled using Maven with dependency caching for faster builds.

```yaml
build:
  name: Build and Test
  runs-on: ubuntu-latest
  
  steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up JDK 21
      uses: actions/setup-java@v4
      with:
        java-version: '21'
        distribution: 'temurin'
        cache: maven  # Caches ~/.m2/repository

    - name: Build with Maven
      run: |
        chmod +x mvnw
        ./mvnw clean compile -B
```

**Key concepts:**
- **`actions/checkout@v4`**: Clones your repository into the runner
- **`cache: maven`**: Caches downloaded dependencies between runs (speeds up builds by ~60%)
- **`-B` flag**: Runs Maven in batch/non-interactive mode
- **`chmod +x mvnw`**: Ensures Maven wrapper is executable (fixes permission issues)

---

### Stage 3: Test

Unit tests are executed and results are uploaded as artifacts for later review.

```yaml
    - name: Run Tests
      run: ./mvnw test -B

    - name: Upload Test Results
      uses: actions/upload-artifact@v4
      if: always()  # Upload even if tests fail
      with:
        name: test-results
        path: target/surefire-reports/
```

**How it works:**
1. Maven runs all tests in `src/test/java`
2. Surefire generates XML reports in `target/surefire-reports/`
3. Reports are uploaded as downloadable artifacts
4. `if: always()` ensures reports are uploaded even on test failure

---

### Stage 4: Package

The application is packaged into a JAR file for containerization.

```yaml
    - name: Package Application
      run: ./mvnw package -DskipTests -B

    - name: Upload JAR Artifact
      uses: actions/upload-artifact@v4
      with:
        name: app-jar
        path: target/*.jar
        retention-days: 7
```

**Output:** `target/task_manager-0.0.1-SNAPSHOT.jar`

---

### Stage 5: CodeQL Security Analysis

GitHub's CodeQL scans the codebase for security vulnerabilities.

```yaml
codeql:
  name: CodeQL Analysis
  runs-on: ubuntu-latest
  needs: build  # Waits for build job to complete
  permissions:
    security-events: write
    actions: read
    contents: read

  steps:
    - name: Initialize CodeQL
      uses: github/codeql-action/init@v3
      with:
        languages: java

    - name: Build for CodeQL
      run: ./mvnw compile -DskipTests -B

    - name: Perform CodeQL Analysis
      uses: github/codeql-action/analyze@v3
```

**What CodeQL detects:**
- SQL injection vulnerabilities
- Cross-site scripting (XSS)
- Path traversal attacks
- Hardcoded credentials
- Insecure deserialization

**Results:** Findings appear in the repository's "Security" → "Code scanning alerts" tab.

---

### Stage 6: Build & Push Container Image

The application is containerized and pushed to GitHub Container Registry (GHCR).

```yaml
container:
  name: Build and Push Container
  runs-on: ubuntu-latest
  needs: [build, codeql]
  if: github.event_name == 'push' && (github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master')
  permissions:
    contents: read
    packages: write  # Required for GHCR push
```

**Condition explained:**
- Only runs on `push` events (not PRs)
- Only runs on `main` or `master` branches
- Prevents container builds on feature branches

#### Authentication

```yaml
    - name: Log in to Container Registry
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
```

**Key concept:** `GITHUB_TOKEN` is automatically provided by GitHub Actions - no manual secret setup required. It has permission to push to GHCR because we declared `packages: write` in permissions.

#### Image Tagging Strategy

```yaml
    - name: Extract metadata for Docker
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ghcr.io/${{ github.repository }}
        tags: |
          type=sha,prefix=
          type=ref,event=branch
          type=raw,value=latest,enable={{is_default_branch}}
```

**Generated tags for commit `abc1234` on `master`:**
```
ghcr.io/aaroncallanga/cicd-pipeline:abc1234
ghcr.io/aaroncallanga/cicd-pipeline:master
ghcr.io/aaroncallanga/cicd-pipeline:latest
```

#### Multi-stage Dockerfile

```dockerfile
# Dockerfile
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Why multi-stage?**
- Build stage: ~800MB (includes Maven, JDK, source code)
- Final image: ~200MB (only JRE + JAR)
- Reduces attack surface and speeds up deployments

---

### Stage 7: Update Kubernetes Manifest

The CI pipeline updates the kustomization file with the new image tag.

```yaml
update-manifest:
  name: Update K8s Manifest
  runs-on: ubuntu-latest
  needs: container

  steps:
    - name: Update Deployment Image Tag
      run: |
        SHORT_SHA=$(echo ${{ github.sha }} | cut -c1-7)
        
        cd kustomize/base
        sed -i "s|newTag:.*|newTag: ${SHORT_SHA}|g" kustomization.yaml
        
        echo "Updated image tag to: ${SHORT_SHA}"

    - name: Commit and Push Changes
      run: |
        git config --global user.name "github-actions[bot]"
        git config --global user.email "github-actions[bot]@users.noreply.github.com"
        
        git add kustomize/
        
        if git diff --staged --quiet; then
          echo "No changes to commit"
        else
          git commit -m "ci: update image tag to ${{ github.sha }}"
          git push
        fi
```

**Before:**
```yaml
# kustomize/base/kustomization.yaml
images:
  - name: ghcr.io/aaroncallanga/cicd-pipeline
    newTag: latest
```

**After (auto-updated by CI):**
```yaml
images:
  - name: ghcr.io/aaroncallanga/cicd-pipeline
    newTag: abc1234
```

**This is the bridge between CI and CD** - the git commit triggers ArgoCD to sync.

---

## Part 2: Continuous Deployment (CD)

### GitOps with ArgoCD

ArgoCD implements the GitOps pattern: **Git is the single source of truth**.

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  GitHub Repo    │         │    ArgoCD       │         │   Kubernetes    │
│                 │  poll   │                 │  apply  │                 │
│ kustomize/      │◄───────►│  Compares Git   │────────►│  task-manager   │
│ overlays/dev    │  (3min) │  vs Cluster     │         │  namespace      │
└─────────────────┘         └─────────────────┘         └─────────────────┘
```

### ArgoCD Application Manifest

```yaml
# argocd/application-dev.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-manager-dev
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/AaronCallanga/task-manager.git
    targetRevision: HEAD  # Always tracks latest commit
    path: kustomize/overlays/dev

  destination:
    server: https://kubernetes.default.svc
    namespace: task-manager

  syncPolicy:
    automated:
      prune: true      # Delete resources removed from Git
      selfHeal: true   # Revert manual changes in cluster
```

**Key settings explained:**

| Setting | Value | Purpose |
|---------|-------|---------|
| `targetRevision: HEAD` | Latest commit | Auto-tracks default branch |
| `prune: true` | Delete orphans | Removes resources not in Git |
| `selfHeal: true` | Revert drift | Undoes manual kubectl changes |

---

### Kustomize Structure

Kustomize allows environment-specific configurations without duplicating YAML.

```
kustomize/
├── base/                          # Shared resources
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── app-deployment.yaml
│   ├── postgres.yaml
│   └── config.yaml
└── overlays/
    ├── dev/                       # Dev-specific patches
    │   ├── kustomization.yaml
    │   └── patches.yaml
    └── prod/                      # Prod-specific patches
        ├── kustomization.yaml
        └── patches.yaml
```

#### Base Kustomization

```yaml
# kustomize/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: task-manager

resources:
  - namespace.yaml
  - config.yaml
  - postgres.yaml
  - app-deployment.yaml

images:
  - name: ghcr.io/aaroncallanga/cicd-pipeline
    newTag: latest  # Updated by CI pipeline
```

#### Dev Overlay

```yaml
# kustomize/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

labels:
  - pairs:
      environment: dev
    includeSelectors: true

patches:
  - path: patches.yaml
```

```yaml
# kustomize/overlays/dev/patches.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task-manager
spec:
  replicas: 1  # Dev only needs 1 replica
  template:
    spec:
      containers:
        - name: task-manager
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "250m"
```

#### Prod Overlay

```yaml
# kustomize/overlays/prod/patches.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task-manager
spec:
  replicas: 3  # Prod has 3 replicas for HA
  template:
    spec:
      containers:
        - name: task-manager
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "1Gi"
              cpu: "1000m"
```

**Building manifests:**
```bash
# Preview what will be applied
kubectl kustomize kustomize/overlays/dev

# Apply directly
kubectl apply -k kustomize/overlays/dev
```

---

### ArgoCD Sync Process

When CI pushes a manifest change:

```
1. CI commits: "ci: update image tag to abc1234"
        │
        ▼
2. GitHub receives push event
        │
        ▼
3. ArgoCD detects Git change (polls every 3 min or webhook)
        │
        ▼
4. ArgoCD compares:
   - Desired state (Git): image=abc1234
   - Actual state (Cluster): image=previous-sha
        │
        ▼
5. ArgoCD applies diff:
   - kubectl apply -k kustomize/overlays/dev
        │
        ▼
6. Kubernetes performs rolling update:
   - Creates new pod with abc1234
   - Waits for readiness probe
   - Terminates old pod
```

---

## Part 3: Kubernetes Resources

### Deployment with Health Checks

```yaml
# kustomize/base/app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task-manager
spec:
  selector:
    matchLabels:
      app: task-manager
  template:
    spec:
      containers:
        - name: task-manager
          image: ghcr.io/aaroncallanga/cicd-pipeline:latest
          ports:
            - containerPort: 8080
          
          # Liveness: Is the app alive?
          livenessProbe:
            httpGet:
              path: /api/tasks
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 3
          
          # Readiness: Can the app receive traffic?
          readinessProbe:
            httpGet:
              path: /api/tasks
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 5
```

**Probe behavior:**
- **Liveness**: Restarts container if 3 consecutive failures
- **Readiness**: Removes from service load balancer if failing

---

### Service with NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: task-manager
spec:
  type: NodePort
  selector:
    app: task-manager
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30080  # Accessible at localhost:30080
```

**Traffic flow:**
```
localhost:30080 → Kind Node → Service → Pod:8080
```

---

## Summary: Complete Flow

```
1. Developer pushes code
        │
        ▼
2. GitHub Actions triggers CI workflow
        │
        ├──► Build with Maven
        ├──► Run unit tests
        ├──► CodeQL security scan
        ├──► Build Docker image
        ├──► Push to GHCR (ghcr.io/...)
        └──► Update kustomize/base/kustomization.yaml with new tag
                │
                ▼
3. CI commits manifest change to Git
        │
        ▼
4. ArgoCD detects change (polls or webhook)
        │
        ▼
5. ArgoCD syncs:
   - Runs: kubectl kustomize kustomize/overlays/dev
   - Applies generated manifests to cluster
        │
        ▼
6. Kubernetes performs rolling update
   - New pods created with updated image
   - Health checks pass
   - Old pods terminated
        │
        ▼
7. Application available at http://localhost:30080/api/tasks
```

---

## Quick Reference

| Component | Purpose | Location |
|-----------|---------|----------|
| CI Workflow | Build, test, containerize | `.github/workflows/ci.yml` |
| Base Manifests | Shared K8s resources | `kustomize/base/` |
| Dev Overlay | Dev-specific patches | `kustomize/overlays/dev/` |
| Prod Overlay | Prod-specific patches | `kustomize/overlays/prod/` |
| ArgoCD Apps | GitOps sync config | `argocd/application-*.yaml` |
| Cluster Config | Kind port mappings | `kind-config.yaml` |
| Setup Scripts | Automated cluster setup | `scripts/` |
