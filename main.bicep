@description('Workload name - used to generate unique resource names')
param workloadName string

@description('Environment (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for the deployment')
param location string

@description('PostgreSQL version')
@allowed(['14', '15', '16'])
param postgresVersion string = '16'

@description('Compute tier')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param computeTier string = 'Burstable'

@description('Storage size in GB')
param storageSizeGb int = 32

// Generate unique names and credentials
var uniqueSuffix = uniqueString(resourceGroup().id, workloadName)
var serverName = 'pgflex-${workloadName}-${environment}-${uniqueSuffix}'
var dbName = '${workloadName}db'
var administratorLogin = 'pgadmin'
var generatedPassword = '${uniqueString(resourceGroup().id, workloadName)}!Aa1${uniqueString(subscription().subscriptionId, workloadName)}'

// SKU mapping based on tier
var skuMap = {
  Burstable: 'Standard_B1ms'
  GeneralPurpose: 'Standard_D2s_v3'
  MemoryOptimized: 'Standard_E2s_v3'
}
var skuName = skuMap[computeTier]

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  name: serverName
  location: location
  sku: {
    name: skuName
    tier: computeTier
  }
  properties: {
    administratorLogin: administratorLogin
    #disable-next-line use-secure-value-for-secure-inputs
    administratorLoginPassword: generatedPassword
    version: postgresVersion

    storage: {
      storageSizeGB: storageSizeGb
    }

    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
}

resource appDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2022-12-01' = {
  parent: pg
  name: dbName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// Allow Azure services (e.g., pipelines running in Azure) to access the server.
// For production, tighten this to specific IP ranges.
resource allowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2022-12-01' = {
  parent: pg
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output serverResourceId string = pg.id
output serverNameOut string = pg.name
output fullyQualifiedDomainName string = pg.properties.fullyQualifiedDomainName
output databaseName string = dbName

// Non-secret “connection info” you can safely share:
output connectionInfo object = {
  host: pg.properties.fullyQualifiedDomainName
  port: 5432
  database: dbName
  // username is usually OK to output; password is NOT.
  username: administratorLogin
  password: generatedPassword
  sslMode: 'require'
}
