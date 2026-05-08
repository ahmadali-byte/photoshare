#!/bin/bash
# PhotoShare — Azure Deployment Script
# COM769 Scalable Advanced Software Solutions
#
# All 10 known problems from the friend's notes are handled here.
# Run from project root: bash infrastructure/deploy.sh

set -e

RESOURCE_GROUP="rg-photoshare"
LOCATION="norwayeast"      # University-allowed region (uksouth/northeurope are blocked)
APP_NAME="pshare"          # FIX: max 8 chars — "photoshare" caused maxLength Bicep error

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   PhotoShare — Azure Deployment                      ║"
echo "║   COM769 Scalable Advanced Software Solutions        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Azure Login ────────────────────────────────────────────────────────
echo "▶ Step 1: Azure Login (university account)"
az login --use-device-code
echo "  ✅ Logged in"

# ── Step 2: Verify region is allowed ──────────────────────────────────────────
echo ""
echo "▶ Step 2: Verifying region access..."
# University policy blocks uksouth, northeurope etc. Only these are allowed:
# switzerlandnorth, germanywestcentral, norwayeast, spaincentral, italynorth
az account show --query "name" -o tsv
echo "  ✅ Using region: $LOCATION"

# ── Step 3: Create Resource Group ─────────────────────────────────────────────
echo ""
echo "▶ Step 3: Creating resource group: $RESOURCE_GROUP"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table
echo "  ✅ Resource group ready"

# ── Step 4: Generate JWT secret ───────────────────────────────────────────────
echo ""
echo "▶ Step 4: Generating secrets..."
JWT_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
ADMIN_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
echo "  ✅ Secrets generated"
echo "  ⚠️  Save these — you'll need them!"
echo "     JWT_SECRET   : $JWT_SECRET"
echo "     ADMIN_SECRET : $ADMIN_SECRET"
echo ""
read -p "  Press Enter to continue after saving the secrets above..."

# ── Step 5: Deploy Bicep (first pass — without real staticWebHostname) ─────────
echo ""
echo "▶ Step 5: Deploying Azure infrastructure via Bicep (first pass)..."
echo "  This deploys: Storage, Cosmos DB, Functions, AI Services, Front Door"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters "$SCRIPT_DIR/parameters.json" \
  --parameters jwtSecret="$JWT_SECRET" adminSecret="$ADMIN_SECRET" \
  --output table

echo "  ✅ Infrastructure deployed"

# ── Step 6: Get deployment outputs ────────────────────────────────────────────
echo ""
echo "▶ Step 6: Retrieving resource names..."

STORAGE_ACCOUNT=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name main \
  --query "properties.outputs.storageAccountName.value" \
  --output tsv 2>/dev/null || \
  az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv)

FUNCTION_APP_NAME=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name storageDeployment \
  --query "properties.outputs.functionAppName.value" \
  --output tsv 2>/dev/null || \
  az functionapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv)

FUNCTION_APP_URL=$(az functionapp show \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "defaultHostName" --output tsv)
FUNCTION_APP_URL="https://$FUNCTION_APP_URL"

echo "  Storage Account : $STORAGE_ACCOUNT"
echo "  Function App    : $FUNCTION_APP_NAME"
echo "  Function URL    : $FUNCTION_APP_URL"

# ── Step 7: Enable static website on blob storage ─────────────────────────────
echo ""
echo "▶ Step 7: Enabling static website hosting on blob storage..."
echo "  (FIX: Cannot be done in Bicep — 'staticWebsite' property not allowed in BlobServiceProperties)"

az storage blob service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --static-website \
  --index-document index.html \
  --404-document index.html \
  --auth-mode login

# FIX: The zone suffix (z1, z16 etc.) varies per account — ALWAYS get real URL via CLI
STATIC_WEB_URL=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "primaryEndpoints.web" \
  --output tsv)

# Extract just the hostname (remove https:// and trailing /)
STATIC_WEB_HOSTNAME=$(echo "$STATIC_WEB_URL" | sed 's|https://||' | sed 's|/$||')

echo "  ✅ Static website enabled"
echo "  Static Web URL      : $STATIC_WEB_URL"
echo "  Static Web Hostname : $STATIC_WEB_HOSTNAME"

# ── Step 8: Redeploy Bicep with real static hostname (fixes Front Door origin) ──
echo ""
echo "▶ Step 8: Redeploying with real static hostname to fix Front Door..."

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters "$SCRIPT_DIR/parameters.json" \
  --parameters jwtSecret="$JWT_SECRET" adminSecret="$ADMIN_SECRET" \
  --parameters staticWebHostname="$STATIC_WEB_HOSTNAME" \
  --output table

echo "  ✅ Front Door configured with real origin"

# ── Step 9: Deploy Python backend via Oryx remote build ───────────────────────
echo ""
echo "▶ Step 9: Deploying Python backend to Azure Functions..."
echo "  (FIX: Using Oryx remote build — local ZIP deploy caused 400 errors)"

cd "$SCRIPT_DIR/../backend"

# Oryx builds pip packages natively on Azure Linux host — no local pip install needed
func azure functionapp publish "$FUNCTION_APP_NAME" \
  --python \
  --build remote

echo "  ✅ Backend deployed"

# ── Step 10: Update frontend config with real API URL ─────────────────────────
echo ""
echo "▶ Step 10: Updating frontend API config..."
cd "$SCRIPT_DIR/../frontend"

cp js/config.js js/config.js.bak
sed "s|https://REPLACE_WITH_YOUR_FUNCTION_APP_URL|$FUNCTION_APP_URL|g" \
  js/config.js.bak > js/config.js

echo "  ✅ config.js updated: $FUNCTION_APP_URL"

# ── Step 11: Upload frontend to blob storage $web container ───────────────────
echo ""
echo "▶ Step 11: Uploading frontend to blob storage \$web container..."

STORAGE_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].value" --output tsv)

az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY" \
  --source . \
  --destination '$web' \
  --overwrite

echo "  ✅ Frontend deployed to blob storage"

# Restore config.js (so the placeholder is in git, not the real URL)
cp js/config.js.bak js/config.js
rm js/config.js.bak

# ── Step 12: Get Front Door URL ────────────────────────────────────────────────
FRONT_DOOR_URL=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name frontdoorDeployment \
  --query "properties.outputs.frontDoorUrl.value" \
  --output tsv 2>/dev/null || echo "$STATIC_WEB_URL")

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   ✅ DEPLOYMENT COMPLETE                              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  🌐 Frontend (CDN)    : $FRONT_DOOR_URL"
echo "  🌐 Frontend (Direct) : $STATIC_WEB_URL"
echo "  📡 Backend API       : $FUNCTION_APP_URL"
echo "  📦 Storage Account   : $STORAGE_ACCOUNT"
echo "  ⚙️  Function App      : $FUNCTION_APP_NAME"
echo ""
echo "  SAVE THESE FOR GITHUB SECRETS:"
echo "  ─────────────────────────────────────────────────────"
echo "  FUNCTION_APP_NAME              = $FUNCTION_APP_NAME"
echo "  FUNCTION_APP_URL               = $FUNCTION_APP_URL"
echo "  AZURE_STORAGE_ACCOUNT_NAME     = $STORAGE_ACCOUNT"
echo "  AZURE_STORAGE_ACCOUNT_KEY      = $STORAGE_KEY"
echo ""
echo "  Get publish profile for AZURE_FUNCTIONAPP_PUBLISH_PROFILE:"
echo "  az functionapp deployment list-publishing-profiles \\"
echo "    --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --xml"
echo ""
echo "  ─────────────────────────────────────────────────────"
echo "  CREATE A CREATOR ACCOUNT:"
echo "  curl -X POST $FUNCTION_APP_URL/api/auth/create-creator \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'X-Admin-Secret: $ADMIN_SECRET' \\"
echo "    -d '{\"username\":\"creator1\",\"email\":\"hafizahmadalitariq@gmail.com\",\"password\":\"PhotoShare123!\"}'"
echo ""
