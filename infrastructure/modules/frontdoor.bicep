// frontdoor.bicep — Azure Front Door Standard
// FIX: Azure CDN classic (Microsoft) was deprecated and no longer allows new profile creation.
// Solution: Use Azure Front Door Standard SKU which replaces Azure CDN classic.
// Front Door provides: global CDN, HTTPS, custom routing, caching, DDoS protection.

@description('Short app name prefix (max 8 chars)')
param appName string

@description('Static website hostname from blob storage (e.g. pshare1234.z1.web.core.windows.net)')
param staticWebHostname string

// Azure Front Door resources must be deployed to 'global' (not a specific region)
resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: '${appName}-frontdoor'
  location: 'global'
  sku: {
    // Standard_AzureFrontDoor replaces deprecated CDN classic
    name: 'Standard_AzureFrontDoor'
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: frontDoorProfile
  name: '${appName}-endpoint'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: frontDoorProfile
  name: '${appName}-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/index.html'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
    sessionAffinityState: 'Disabled'
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: '${appName}-blob-origin'
  properties: {
    // Points to blob storage static website endpoint
    // FIX: The zone suffix (z1, z16 etc.) varies per account — always get real URL via CLI:
    // az storage account show --name <name> --query "primaryEndpoints.web" -o tsv
    hostName: staticWebHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: staticWebHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: frontDoorEndpoint
  name: '${appName}-route'
  dependsOn: [origin] // must wait for origin to be created
  properties: {
    originGroup: { id: originGroup.id }
    supportedProtocols: ['Http', 'Https']
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    cacheConfiguration: {
      queryStringCachingBehavior: 'IgnoreQueryString'
      compressionSettings: {
        isCompressionEnabled: true
        contentTypesToCompress: [
          'text/html'
          'text/css'
          'application/javascript'
          'application/json'
        ]
      }
    }
  }
}

// Front Door hostname (e.g. pshare-endpoint-abc123.z01.azurefd.net)
output frontDoorEndpointHostname string = frontDoorEndpoint.properties.hostName
output frontDoorUrl string = 'https://${frontDoorEndpoint.properties.hostName}'
