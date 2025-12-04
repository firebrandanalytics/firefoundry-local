#!/bin/bash
# FireFoundry Internal Template Setup
# Downloads the internal environment template from Azure Blob Storage
#
# Prerequisites:
#   - Azure CLI installed (az)
#   - Logged in: az login
#   - Subscription set: az account set --subscription "Firebrand R&D"
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/firebrandanalytics/firefoundry-local/main/scripts/setup-ff-template.sh | bash

set -e

# Configuration
STORAGE_ACCOUNT="firebrand"
CONTAINER_NAME="internal"
BLOB_NAME="internal.json"
TEMPLATE_DIR="$HOME/.ff/environments/templates"
TEMPLATE_FILE="$TEMPLATE_DIR/internal.json"

echo "FireFoundry Internal Template Setup"
echo "===================================="
echo ""

# Check for Azure CLI
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI (az) is not installed."
    echo "Install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo "Error: Not logged in to Azure."
    echo "Run: az login"
    exit 1
fi

# Check subscription
CURRENT_SUB=$(az account show --query name -o tsv 2>/dev/null)
if [[ "$CURRENT_SUB" != "Firebrand R&D" ]]; then
    echo "Warning: Current subscription is '$CURRENT_SUB'"
    echo "Switching to 'Firebrand R&D'..."
    az account set --subscription "Firebrand R&D" || {
        echo "Error: Could not switch to 'Firebrand R&D' subscription."
        echo "Make sure you have access to this subscription."
        exit 1
    }
fi

echo "Authenticated as: $(az account show --query user.name -o tsv)"
echo "Subscription: $(az account show --query name -o tsv)"
echo ""

# Create directory
echo "Creating template directory..."
mkdir -p "$TEMPLATE_DIR"

# Download template from Azure Blob Storage
echo "Downloading internal template..."
az storage blob download \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER_NAME" \
    --name "$BLOB_NAME" \
    --file "$TEMPLATE_FILE" \
    --auth-mode login \
    --only-show-errors

echo ""
echo "Template installed successfully!"
echo "Location: $TEMPLATE_FILE"
echo ""
echo "You can now create environments with:"
echo "  ff-cli environment create --template internal --name <env-name>"
