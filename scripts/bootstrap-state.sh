#!/usr/bin/env bash
###############################################################################
# One-time bootstrap: creates the Terraform remote state backend.
# Run with an account that has Owner on the management subscription.
#
# Usage: ./scripts/bootstrap-state.sh <subscription-id> [location]
###############################################################################
set -euo pipefail

SUBSCRIPTION_ID="${1:?Usage: $0 <subscription-id> [location]}"
LOCATION="${2:-centralindia}"
RG_NAME="rg-tfstate-prod-cin"
SA_NAME="sttfstate$(openssl rand -hex 4)"
CONTAINER="tfstate"

az account set --subscription "$SUBSCRIPTION_ID"

echo ">> Creating resource group $RG_NAME"
az group create --name "$RG_NAME" --location "$LOCATION" \
  --tags Environment=prod Owner=platform-team CostCenter=CC-PLATFORM ManagedBy=script

echo ">> Creating storage account $SA_NAME"
az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --location "$LOCATION" \
  --sku Standard_GRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

echo ">> Enabling versioning + soft delete on blobs (state protection)"
az storage account blob-service-properties update \
  --account-name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30

echo ">> Creating container $CONTAINER"
az storage container create \
  --name "$CONTAINER" \
  --account-name "$SA_NAME" \
  --auth-mode login

echo ""
echo "=========================================================="
echo "Backend ready. Update every environments/*/backend.hcl with:"
echo "  resource_group_name  = \"$RG_NAME\""
echo "  storage_account_name = \"$SA_NAME\""
echo "  container_name       = \"$CONTAINER\""
echo "=========================================================="
