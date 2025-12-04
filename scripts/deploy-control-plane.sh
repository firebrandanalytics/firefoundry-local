#!/bin/bash
set -e

# FireFoundry Control Plane Deployment Script
# Installs Flux CRDs and deploys/upgrades the control plane

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Defaults
NAMESPACE="ff-control-plane"
RELEASE_NAME="firefoundry-control"
CHART_NAME="firebrandanalytics/firefoundry-control-plane"
VALUES_FILE="$REPO_ROOT/control-plane/values.yaml"
SECRETS_FILE="$REPO_ROOT/control-plane/secrets.yaml"
CHART_VERSION=""  # Empty = latest cached version

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy or upgrade FireFoundry Control Plane to a local Kubernetes cluster"
    echo ""
    echo "Options:"
    echo "  -v, --version VERSION    Specify chart version (default: latest cached)"
    echo "  -n, --namespace NS       Kubernetes namespace (default: $NAMESPACE)"
    echo "  -r, --release NAME       Helm release name (default: $RELEASE_NAME)"
    echo "  --skip-crds              Skip Flux CRD installation"
    echo "  --dry-run                Perform a dry run (helm --dry-run)"
    echo "  --debug                  Enable debug output"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                       # Deploy with latest cached chart"
    echo "  $0 -v 0.2.0              # Deploy specific version"
    echo "  $0 --dry-run             # Preview what would be deployed"
    echo ""
    echo "Prerequisites:"
    echo "  - kubectl configured for your cluster (minikube, k3d, etc.)"
    echo "  - Helm 3 installed"
    echo "  - control-plane/secrets.yaml created (copy from secrets.template.yaml)"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Parse arguments
SKIP_CRDS=false
DRY_RUN=false
DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            CHART_VERSION="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --skip-crds)
            SKIP_CRDS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  FireFoundry Control Plane Deployment"
echo "=========================================="
echo ""

# Verify prerequisites
log_step "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed. Please install it first."
    echo "  brew install kubectl  # macOS"
    echo "  https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
log_info "kubectl: OK"

if ! command -v helm &> /dev/null; then
    log_error "helm is not installed. Please install it first."
    echo "  brew install helm  # macOS"
    echo "  https://helm.sh/docs/intro/install/"
    exit 1
fi
log_info "helm: OK"

# Check kubectl context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
if [[ "$CURRENT_CONTEXT" == "none" ]]; then
    log_error "No kubectl context configured. Please start your cluster first."
    echo "  minikube start"
    echo "  k3d cluster create firefoundry"
    exit 1
fi
log_info "kubectl context: $CURRENT_CONTEXT"

# Verify cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Is your cluster running?"
    exit 1
fi
log_info "Cluster connection: OK"

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
    log_error "Values file not found: $VALUES_FILE"
    exit 1
fi
log_info "Values file: $VALUES_FILE"

# Check secrets file
if [[ ! -f "$SECRETS_FILE" ]]; then
    log_warn "Secrets file not found: $SECRETS_FILE"
    log_warn "Continuing without secrets (some features may not work)"
    log_info "To create secrets: cp control-plane/secrets.template.yaml control-plane/secrets.yaml"
fi

echo ""

# Install Flux CRDs
if [[ "$SKIP_CRDS" == "false" ]]; then
    log_step "Installing Flux CRDs..."

    kubectl apply -f https://raw.githubusercontent.com/fluxcd/helm-controller/refs/heads/main/config/crd/bases/helm.toolkit.fluxcd.io_helmreleases.yaml
    kubectl apply -f https://raw.githubusercontent.com/fluxcd/source-controller/refs/heads/main/config/crd/bases/source.toolkit.fluxcd.io_helmrepositories.yaml
    kubectl apply -f https://raw.githubusercontent.com/fluxcd/source-controller/refs/heads/main/config/crd/bases/source.toolkit.fluxcd.io_helmcharts.yaml
    kubectl apply -f https://raw.githubusercontent.com/fluxcd/source-controller/refs/heads/main/config/crd/bases/source.toolkit.fluxcd.io_buckets.yaml
    kubectl apply -f https://raw.githubusercontent.com/fluxcd/source-controller/refs/heads/main/config/crd/bases/source.toolkit.fluxcd.io_gitrepositories.yaml
    kubectl apply -f https://raw.githubusercontent.com/fluxcd/source-controller/refs/heads/main/config/crd/bases/source.toolkit.fluxcd.io_ocirepositories.yaml

    log_info "Flux CRDs installed"
else
    log_warn "Skipping Flux CRD installation (--skip-crds)"
fi

echo ""

# Update Helm repo
log_step "Updating Helm repository..."
helm repo add firebrandanalytics https://firebrandanalytics.github.io/ff_infra 2>/dev/null || true
helm repo update firebrandanalytics
log_info "Helm repository updated"

echo ""

# Create namespace if it doesn't exist
log_step "Preparing namespace..."
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
else
    log_info "Namespace exists: $NAMESPACE"
fi

echo ""

# Build helm command
log_step "Deploying FireFoundry Control Plane..."

HELM_CMD="helm upgrade --install $RELEASE_NAME $CHART_NAME"
HELM_CMD="$HELM_CMD --namespace $NAMESPACE"
HELM_CMD="$HELM_CMD -f $VALUES_FILE"

# Add secrets file if it exists
if [[ -f "$SECRETS_FILE" ]]; then
    HELM_CMD="$HELM_CMD -f $SECRETS_FILE"
    log_info "Including secrets file"
fi

# Add version flag if specified
if [[ -n "$CHART_VERSION" ]]; then
    log_info "Chart version: $CHART_VERSION"
    HELM_CMD="$HELM_CMD --version $CHART_VERSION"
else
    LATEST_VERSION=$(helm search repo firebrandanalytics/firefoundry-control-plane --output json 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
    log_info "Chart version: ${LATEST_VERSION:-latest cached}"
fi

# Add dry-run flag if specified
if [[ "$DRY_RUN" == "true" ]]; then
    HELM_CMD="$HELM_CMD --dry-run"
    log_warn "DRY RUN MODE - no changes will be made"
fi

# Add debug flag if specified
if [[ "$DEBUG" == "true" ]]; then
    HELM_CMD="$HELM_CMD --debug"
    log_info "Command: $HELM_CMD"
fi

echo ""

# Execute helm command
eval $HELM_CMD

echo ""

if [[ "$DRY_RUN" == "false" ]]; then
    echo "=========================================="
    echo "  Deployment Complete!"
    echo "=========================================="
    echo ""
    log_info "Check pod status:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo ""
    log_info "Check helm release:"
    echo "  helm status $RELEASE_NAME -n $NAMESPACE"
    echo ""
    log_info "Access Kong Gateway:"
    if [[ "$CURRENT_CONTEXT" == *"minikube"* ]]; then
        echo "  minikube service firefoundry-control-firefoundry-control-plane-kong-proxy -n $NAMESPACE --url"
    else
        echo "  http://localhost:30080"
    fi
    echo ""
    log_info "Next steps:"
    echo "  1. Monitor with k9s"
    echo "  2. Install ff-cli from: https://github.com/firebrandanalytics/ff-cli-releases"
    echo "  3. Download internal template: curl -fsSL https://raw.githubusercontent.com/firebrandanalytics/firefoundry-local/main/scripts/setup-ff-template.sh | bash"
    echo "  4. Create an environment: ff-cli environment create --template internal --name my-env"
else
    log_info "Dry run complete - review output above"
fi
