// main.bicep — PhotoShare Infrastructure Orchestrator
// COM769 Scalable Advanced Software Solutions
//
// UNIVERSITY REGION RESTRICTION:
// Ulster University Azure for Students only allows these regions:
//   switzerlandnorth, germanywestcentral, norwayeast, spaincentral, italynorth
// Default: norwayeast
//
// Deploy command:
// az deployment group create \
//   --resource-group rg-photoshare \
//   --template-file infrastructure/main.bicep \
//   --parameters infrastructure/parameters.json \
//   --parameters jwtSecret="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

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

@description('JWT secret for token signing — auto-generated if using deploy.sh')
@secure()
param jwtSecret string

@description('Admin secret for creator account creation')
@secure()
param adminSecret string = 'ChangeThisAdminSecret!'

@description('Static website hostname — set after first deployment (leave blank initially)')
param staticWebHostname string = 'placeholder.z1.web.core.windows.net'

// ── Module 1: Storage ─────────────────────────────────────────────────────────
module storage 'modules/storage.bicep' = {
  name: 'storageDeployment'
  params: {
    appName: appName
    location: location
  }
}

// ── Module 2: Cosmos DB ───────────────────────────────────────────────────────
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

// Storage connection string (built from storage module outputs)
var storageConnStr = 'DefaultEndpointsProtocol=https;AccountName=${storage.outputs.storageAccountName};AccountKey=${listKeys(resourceId('Microsoft.Storage/storageAccounts', storage.outputs.storageAccountName), '2023-01-01').keys[0].value};EndpointSuffix=core.windows.net'

// ── Module 4: Function App ────────────────────────────────────────────────────
module functionapp 'modules/functionapp.bicep' = {
  name: 'functionappDeployment'
  params: {
    appName: appName
    location: location
    storageConnectionString: storageConnStr
    cosmosEndpoint: cosmosdb.outputs.cosmosEndpoint
    cosmosKey: cosmosdb.outputs.cosmosPrimaryKey
    blobConnectionString: storageConnStr
    visionEndpoint: aiservices.outputs.visionEndpoint
    visionKey: aiservices.outputs.visionKey
    languageEndpoint: aiservices.outputs.languageEndpoint
    languageKey: aiservices.outputs.languageKey
    jwtSecret: jwtSecret
    adminSecret: adminSecret
    frontendUrl: '*'
  }
  dependsOn: [storage, cosmosdb, aiservices]
}

// ── Module 5: Front Door (CDN + Routing) ──────────────────────────────────────
// NOTE: Deploy this AFTER you have the real staticWebHostname from blob storage.
// On first deployment, leave staticWebHostname as default placeholder.
// On second deployment, provide the real hostname.
module frontdoor 'modules/frontdoor.bicep' = {
  name: 'frontdoorDeployment'
  params: {
    appName: appName
    staticWebHostname: staticWebHostname
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output storageAccountName string = storage.outputs.storageAccountName
output cosmosAccountName string = cosmosdb.outputs.cosmosAccountName
output functionAppName string = functionapp.outputs.functionAppName
output functionAppUrl string = functionapp.outputs.functionAppUrl
output frontDoorUrl string = frontdoor.outputs.frontDoorUrl

// IMPORTANT: After deployment, run these CLI commands:
//
// 1. Get real static website URL:
//    az storage account show --name <storageAccountName> --resource-group rg-photoshare --query "primaryEndpoints.web" -o tsv
//
// 2. Enable static website hosting (cannot be done in Bicep):
//    az storage blob service-properties update \
//      --account-name <storageAccountName> \
//      --static-website \
//      --index-document index.html \
//      --404-document index.html \
//      --auth-mode login
//
// 3. Redeploy with real staticWebHostname to fix Front Door origin
