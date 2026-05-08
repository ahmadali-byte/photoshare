// storage.bicep — Azure Blob Storage
// Hosts photo files (photos container) + static frontend ($web container)
// NOTE: Static website hosting must be enabled via CLI after deployment (not supported in Bicep)

@description('Short app name prefix (max 8 chars)')
param appName string

@description('Azure region (must be university-allowed region)')
param location string

// Storage account name must be globally unique, lowercase, 3-24 chars
var storageAccountName = '${appName}stor${uniqueString(resourceGroup().id)}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
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

// Container for uploaded photos (public read access)
resource photosContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'photos'
  properties: { publicAccess: 'Blob' }
}

// $web container is created automatically when static website is enabled via CLI
// Do NOT define it here — Bicep cannot enable staticWebsite on BlobServiceProperties

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
// Connection string built here (not in main.bicep) to avoid BCP181 listKeys error
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

// NOTE: After deployment run this CLI command to get the real static web URL:
// az storage account show --name <storageAccountName> --resource-group <rg> --query "primaryEndpoints.web" -o tsv
