#!/bin/bash
# PhotoShare — Azure Deployment Script
# Run this ONCE to set up all Azure resources
# Prerequisites: Azure CLI installed, logged in with university account

set -e

# ── Configuration ─────────────────────────────────────────────────────────────
RESOURCE_GROUP="photoshare-rg"
LOCATION="uksouth"
BASE_NAME="photoshare"

echo ""
echo "======================================================"
echo "  PhotoShare — Azure Deployment"
echo "  COM769 Scalable Advanced Software Solutions"
echo "======================================================"
echo ""

# ── Step 1: Login ─────────────────────────────────────────────────────────────
echo "▶ Step 1: Azure Login"
echo "  Run: az login --use-device-code"
echo "  Then press Enter to continue..."
read -r

# ── Step 2: Resource Group ────────────────────────────────────────────────────
echo ""
echo "▶ Step 2: Creating Resource Group: $RESOURCE_GROUP"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
echo "  ✅ Resource group created"

# ── Step 3: Deploy Bicep Infrastructure ──────────────────────────────────────
echo ""
echo "▶ Step 3: Deploying Azure Infrastructure via Bicep..."
echo "  This creates: Storage, Cosmos DB, Functions, Cognitive Services"
echo ""

read -s -p "  Enter JWT secret (make it long & random): " JWT_SECRET
echo ""
read -s -p "  Enter Admin secret (for creating creator accounts): " ADMIN_SECRET
echo ""

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters baseName="$BASE_NAME" location="$LOCATION" jwtSecret="$JWT_SECRET" adminSecret="$ADMIN_SECRET" \
  --output table

echo "  ✅ Infrastructure deployed"

# ── Step 4: Get Outputs ───────────────────────────────────────────────────────
echo ""
echo "▶ Step 4: Retrieving deployment outputs..."

FUNCTION_URL=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name main \
  --query "properties.outputs.functionAppUrl.value" \
  --output tsv)

STATIC_URL=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name main \
  --query "properties.outputs.staticWebAppUrl.value" \
  --output tsv)

FUNCTION_APP_NAME=$(az functionapp list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" --output tsv)

echo ""
echo "======================================================"
echo "  ✅ DEPLOYMENT COMPLETE"
echo "======================================================"
echo ""
echo "  📡 Function App URL:   $FUNCTION_URL"
echo "  🌐 Static Web App URL: $STATIC_URL"
echo "  📦 Function App Name:  $FUNCTION_APP_NAME"
echo ""

# ── Step 5: Deploy Backend ────────────────────────────────────────────────────
echo "▶ Step 5: Deploying Python backend to Azure Functions..."
cd ../backend
pip install -r requirements.txt --target=".python_packages/lib/site-packages"
func azure functionapp publish "$FUNCTION_APP_NAME" --python
echo "  ✅ Backend deployed"

# ── Step 6: Update Frontend Config ────────────────────────────────────────────
echo ""
echo "▶ Step 6: Updating frontend API URL..."
cd ../frontend
sed "s|https://REPLACE_WITH_YOUR_FUNCTION_APP_URL|$FUNCTION_URL|g" js/config.js > js/config.js.tmp
mv js/config.js.tmp js/config.js
echo "  ✅ Frontend config updated"

# ── Step 7: Deploy Frontend ───────────────────────────────────────────────────
echo ""
echo "▶ Step 7: Deploying frontend to Azure Static Web Apps..."
STATIC_APP_NAME=$(az staticwebapp list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" --output tsv)

az staticwebapp deploy \
  --name "$STATIC_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --source "." \
  --no-wait

echo ""
echo "======================================================"
echo "  🎉 ALL DONE!"
echo "======================================================"
echo ""
echo "  Your app: $STATIC_URL"
echo ""
echo "  Next: Create a creator account via:"
echo "  curl -X POST $FUNCTION_URL/api/auth/create-creator \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'X-Admin-Secret: $ADMIN_SECRET' \\"
echo "    -d '{\"username\": \"creator1\", \"email\": \"creator@example.com\", \"password\": \"YourPassword123\"}'"
echo ""
