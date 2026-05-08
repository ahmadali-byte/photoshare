// aiservices.bicep — Azure AI / Cognitive Services
// Computer Vision (F0): 5000 transactions/month free — auto-tags photos
// Language Service (F0): 5000 records/month free — sentiment analysis on comments

@description('Short app name prefix (max 8 chars)')
param appName string

@description('Azure region')
param location string

resource visionService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: '${appName}-vision-${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'F0' }
  kind: 'ComputerVision'
  properties: {
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

resource languageService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: '${appName}-lang-${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'F0' }
  kind: 'TextAnalytics'
  properties: {
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

output visionEndpoint string = visionService.properties.endpoint
output visionKey string = visionService.listKeys().key1
output languageEndpoint string = languageService.properties.endpoint
output languageKey string = languageService.listKeys().key1
