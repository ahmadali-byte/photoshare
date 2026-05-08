// functionapp.bicep — Azure Functions (Consumption plan, Python 3.11, Linux)
// Free tier: 1 million executions/month
// FIX: Added WEBSITE_CONTENTAZUREFILECONNECTIONSTRING and WEBSITE_CONTENTSHARE
//      which are required for Consumption plan Functions — missing these caused 400 errors.

@description('Short app name prefix (max 8 chars)')
param appName string

@description('Azure region')
param location string

@description('Storage account connection string (for Functions runtime)')
param storageConnectionString string

@description('Cosmos DB endpoint')
param cosmosEndpoint string

@description('Cosmos DB primary key')
@secure()
param cosmosKey string

@description('Blob storage connection string (for photo uploads)')
param blobConnectionString string

@description('Computer Vision endpoint')
param visionEndpoint string

@description('Computer Vision key')
@secure()
param visionKey string

@description('Language Service endpoint')
param languageEndpoint string

@description('Language Service key')
@secure()
param languageKey string

@description('JWT secret for token signing')
@secure()
param jwtSecret string

@description('Admin secret for creator account creation')
@secure()
param adminSecret string

@description('Frontend URL for CORS (blob storage static website URL)')
param frontendUrl string = '*'

// Application Insights for monitoring
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${appName}-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appName}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Consumption plan (Y1/Dynamic) — scales to zero, pay per execution
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${appName}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // required for Linux
  }
}

var contentShareName = '${appName}func${uniqueString(resourceGroup().id)}'

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: '${appName}-func-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      appSettings: [
        // FIX: These two settings are REQUIRED for Consumption plan on Linux.
        // Missing them causes HTTP 400 during Function App creation.
        { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING', value: storageConnectionString }
        { name: 'WEBSITE_CONTENTSHARE', value: contentShareName }

        { name: 'AzureWebJobsStorage', value: storageConnectionString }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY', value: appInsights.properties.InstrumentationKey }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
        { name: 'COSMOS_KEY', value: cosmosKey }
        { name: 'COSMOS_DATABASE', value: 'photoshare' }
        { name: 'BLOB_CONNECTION_STRING', value: blobConnectionString }
        { name: 'BLOB_CONTAINER', value: 'photos' }
        { name: 'VISION_ENDPOINT', value: visionEndpoint }
        { name: 'VISION_KEY', value: visionKey }
        { name: 'LANGUAGE_ENDPOINT', value: languageEndpoint }
        { name: 'LANGUAGE_KEY', value: languageKey }
        { name: 'JWT_SECRET', value: jwtSecret }
        { name: 'ADMIN_SECRET', value: adminSecret }
        { name: 'FRONTEND_URL', value: frontendUrl }
        // Oryx remote build — builds pip packages on Azure Linux host
        { name: 'ENABLE_ORYX_BUILD', value: 'true' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output appInsightsKey string = appInsights.properties.InstrumentationKey
