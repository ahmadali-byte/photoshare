// PhotoShare - Azure Infrastructure
// Deploy with: az deployment group create --resource-group <rg> --template-file main.bicep --parameters @parameters.json

@description('Base name for all resources (lowercase, no spaces)')
param baseName string = 'photoshare'

@description('Azure region')
param location string = resourceGroup().location

@description('JWT secret for token signing')
@secure()
param jwtSecret string

@description('Admin secret for creator account creation')
@secure()
param adminSecret string

// ── Storage Account ───────────────────────────────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${baseName}stor${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource photosContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'photos'
  properties: { publicAccess: 'Blob' }
}

// ── Cosmos DB ─────────────────────────────────────────────────────────────────
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: '${baseName}-cosmos-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [{ locationName: location, failoverPriority: 0 }]
    capabilities: [{ name: 'EnableServerless' }]
    enableFreeTier: true
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'photoshare'
  properties: {
    resource: { id: 'photoshare' }
  }
}

var containers = ['users', 'photos', 'comments', 'ratings']
resource cosmosContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = [for name in containers: {
  parent: cosmosDatabase
  name: name
  properties: {
    resource: {
      id: name
      partitionKey: { paths: ['/id'], kind: 'Hash' }
    }
  }
}]

// ── Cognitive Services — Computer Vision ─────────────────────────────────────
resource visionService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: '${baseName}-vision-${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'F0' }
  kind: 'ComputerVision'
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// ── Cognitive Services — Language (Text Analytics) ────────────────────────────
resource languageService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: '${baseName}-lang-${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'F0' }
  kind: 'TextAnalytics'
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// ── Application Insights ──────────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${baseName}-logs'
  location: location
  properties: { sku: { name: 'PerGB2018' } }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ── App Service Plan (Consumption - Serverless) ───────────────────────────────
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${baseName}-plan'
  location: location
  sku: { name: 'Y1'; tier: 'Dynamic' }
  properties: {}
}

// ── Azure Function App ────────────────────────────────────────────────────────
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: '${baseName}-func-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      pythonVersion: '3.11'
      appSettings: [
        { name: 'AzureWebJobsStorage'; value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net' }
        { name: 'FUNCTIONS_EXTENSION_VERSION'; value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME'; value: 'python' }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY'; value: appInsights.properties.InstrumentationKey }
        { name: 'COSMOS_ENDPOINT'; value: cosmosAccount.properties.documentEndpoint }
        { name: 'COSMOS_KEY'; value: cosmosAccount.listKeys().primaryMasterKey }
        { name: 'COSMOS_DATABASE'; value: 'photoshare' }
        { name: 'BLOB_CONNECTION_STRING'; value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net' }
        { name: 'BLOB_CONTAINER'; value: 'photos' }
        { name: 'VISION_ENDPOINT'; value: visionService.properties.endpoint }
        { name: 'VISION_KEY'; value: visionService.listKeys().key1 }
        { name: 'LANGUAGE_ENDPOINT'; value: languageService.properties.endpoint }
        { name: 'LANGUAGE_KEY'; value: languageService.listKeys().key1 }
        { name: 'JWT_SECRET'; value: jwtSecret }
        { name: 'ADMIN_SECRET'; value: adminSecret }
        { name: 'FRONTEND_URL'; value: '*' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE'; value: '1' }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
    }
    httpsOnly: true
  }
}

// ── Azure Static Web App ──────────────────────────────────────────────────────
resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: '${baseName}-web'
  location: location
  sku: { name: 'Free'; tier: 'Free' }
  properties: {
    buildProperties: {
      appLocation: '/frontend'
      outputLocation: ''
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'
output storageAccountName string = storageAccount.name
output cosmosAccountName string = cosmosAccount.name
