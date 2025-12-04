# FireFoundry Local Development

Get FireFoundry running locally on minikube or k3d for development and testing.

## Overview

This repository provides everything you need to run FireFoundry locally:

1. **Control Plane** - Core infrastructure (Kong Gateway, Flux, Helm API, FF Console)
2. **Environments** - Managed via `ff-cli` for deploying FireFoundry Core services

## Prerequisites

- **Kubernetes cluster**: minikube, k3d, or Docker Desktop with Kubernetes
- **kubectl**: Configured to access your cluster
- **Helm 3**: Package manager for Kubernetes
- **ff-cli**: FireFoundry CLI tool (for environment management)

### Install Prerequisites

```bash
# macOS with Homebrew
brew install kubectl helm minikube
```

### Get the FireFoundry CLI

FF-CLI: [releases](https://github.com/firebrandanalytics/ff-cli-releases)

## Quick Start

### 1. Start Your Local Cluster

**minikube:**
```bash
minikube start --memory=8192 --cpus=4
```

**k3d:**
```bash
k3d cluster create firefoundry-dev --servers 3 --agents 2 --api-port 127.0.0.1:6445 --port '8080:80@loadbalancer'
```

### 2. Configure Secrets

Copy the secrets template and fill in your values:

```bash
cp control-plane/secrets.template.yaml control-plane/secrets.yaml
# Edit secrets.yaml with your actual credentials
```

> **Important**: `secrets.yaml` is gitignored and should never be committed.

### 3. Deploy the Control Plane

```bash
./scripts/deploy-control-plane.sh
```

This will:
- Install Flux CRDs (required for Helm API)
- Deploy FireFoundry Control Plane with Kong Gateway, Flux controllers, and Helm API

### 4. Verify Deployment

```bash
kubectl get pods -n ff-control-plane
```

All pods should be Running within a few minutes.

### 5. Access Services

**Via minikube:**
```bash
# Get the Kong proxy URL
minikube service firefoundry-control-firefoundry-control-plane-kong-proxy -n ff-control-plane --url
```

**Via k3d:**
```bash
# Kong is available at http://localhost:30080
curl http://localhost:30080/health
```

## Creating Environments (FireFoundry Core)

Once the control plane is running, use `ff-cli` to create environments:

```bash
# Configure ff-cli to use your local cluster
ff-cli config set helm-api-url http://localhost:30080/management/helm

# Create a new environment
ff-cli environment create my-env --template internal

# List environments
ff-cli environment list

# Delete an environment
ff-cli environment delete my-env
```

## Directory Structure

```
firefoundry-local/
├── README.md                           # This file
├── scripts/
│   └── deploy-control-plane.sh         # Control plane deployment script
└── control-plane/
    ├── values.yaml                     # Control plane configuration
    └── secrets.template.yaml           # Template for secrets (copy to secrets.yaml)
```

## Configuration

### Control Plane Components

| Component | Default | Description |
|-----------|---------|-------------|
| Kong Gateway | Enabled | API Gateway for all services |
| Flux | Enabled | GitOps controllers for HelmRelease management |
| Helm API | Enabled | HTTP API for environment management |
| FF Console | Enabled | Management UI |
| PostgreSQL | Enabled | Shared database for control plane services |
| Concourse | Disabled | CI/CD (enable if needed) |
| Harbor | Disabled | Container registry (enable if needed) |

### Customizing Values

Edit `control-plane/values.yaml` to customize your deployment:

```yaml
# Example: Change Kong proxy to LoadBalancer for cloud deployments
kong:
  proxy:
    type: LoadBalancer
```

## Troubleshooting

### Pods not starting

Check events:
```bash
kubectl get events -n ff-control-plane --sort-by='.lastTimestamp'
```

### Kong not accessible

Verify the service:
```bash
kubectl get svc -n ff-control-plane | grep kong
```

### Flux CRDs missing

Re-run with CRD installation:
```bash
./scripts/deploy-control-plane.sh
```

### Reset everything

```bash
helm uninstall firefoundry-control -n ff-control-plane
kubectl delete namespace ff-control-plane
```

## Next Steps

- [FireFoundry Documentation](https://github.com/firebrandanalytics/firefoundry)
- [ff-cli Documentation](https://github.com/firebrandanalytics/ff-cli)
- [Helm Charts](https://firebrandanalytics.github.io/ff_infra)
