// main.bicep — PhotoShare Infrastructure Orchestrator
// COM769 Scalable Advanced Software Solutions
//
// UNIVERSITY REGION RESTRICTION:
// Ulster University Azure for Students only allows these regions:
//   switzerlandnorth, germanywestcentral, norwayeast, spaincentral, italynorth
// Default: norwayeast
//
// NOTE: Azure Front Door and Cosmos DB free tier are NOT available on Student subscriptions.
// Frontend is served directly from Azure Blob Storage static website hosting.

@description('Short app name — max 8 chars (longer names cause Bicep maxLength errors)')
@maxLength(8)
param appName string = 'pshare'

@description('Azure region — must be university-allowed region')
@allowed([
  'norwayeast'
  'switzerlandnorth'
  'germanywestcentral'
  'spaincentral'
  'italynorth'
])
param location string = 'norwayeast'

@description('JWT secret for token signing')
@secure()
param jwtSecret string

@description('Admin secret for creator account creation')
@secure()
param adminSecret string = ''

// ── Module 1: Storage ─────────────────────────────────────────────────────────
module storage 'modules/storage.bicep' = {
  name: 'storageDeployment'
  params: {
    appName: appName
    location: location
  }
}

// ── Module 2: Cosmos DB (serverless, free tier disabled — one per subscription) ──
module cosmosdb 'modules/cosmosdb.bicep' = {
  name: 'cosmosdbDeployment'
  params: {
    appName: appName
    location: location
  }
}

// ── Module 3: AI Services ─────────────────────────────────────────────────────
module aiservices 'modules/aiservices.bicep' = {
  name: 'aiServicesDeployment'
  params: {
    appName: appName
    location: location
  }
}

// ── Module 4: Function App ────────────────────────────────────────────────────
module functionapp 'modules/functionapp.bicep' = {
  name: 'functionappDeployment'
  params: {
    appName: appName
    location: location
    storageConnectionString: storage.outputs.storageConnectionString
    cosmosEndpoint: cosmosdb.outputs.cosmosEndpoint
    cosmosKey: cosmosdb.outputs.cosmosPrimaryKey
    blobConnectionString: storage.outputs.storageConnectionString
    visionEndpoint: aiservices.outputs.visionEndpoint
    visionKey: aiservices.outputs.visionKey
    languageEndpoint: aiservices.outputs.languageEndpoint
    languageKey: aiservices.outputs.languageKey
    jwtSecret: jwtSecret
    adminSecret: adminSecret
    frontendUrl: '*'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output storageAccountName string = storage.outputs.storageAccountName
output functionAppName string = functionapp.outputs.functionAppName
output functionAppUrl string = functionapp.outputs.functionAppUrl

// After deployment run this to get the static website URL:
// az storage account show --name <storageAccountName> --resource-group rg-photoshare --query "primaryEndpoints.web" -o tsv
