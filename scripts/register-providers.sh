#!/usr/bin/env bash
# Registers required resource providers on a subscription (run once per sub).
set -euo pipefail
SUBSCRIPTION_ID="${1:?Usage: $0 <subscription-id>}"
az account set --subscription "$SUBSCRIPTION_ID"
for p in Microsoft.Network Microsoft.Storage Microsoft.KeyVault Microsoft.OperationalInsights \
         Microsoft.RecoveryServices Microsoft.Automation Microsoft.PolicyInsights \
         Microsoft.Management Microsoft.Consumption Microsoft.Insights; do
  echo "Registering $p"
  az provider register --namespace "$p" --wait &
done
wait
echo "All providers registered."
