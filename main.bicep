@description('Azure region for the deployment')
param location string = resourceGroup().location

@description('PostgreSQL Flexible Server name (must be globally unique)')
param serverName string

@description('Database name to create on the server')
param dbName string = 'appdb'

@description('Admin username (cannot be "postgres")')
param administratorLogin string

@description('PostgreSQL version')
@allowed([
  '14'
  '15'
  '16'
])
param version string = '16'

@description('Compute SKU name. Example: Standard_D2s_v3')
param skuName string = 'Standard_D2s_v3'

@description('Storage size in GB')
param storageSizeGb int = 32

// Generate a random password for demo purposes
var generatedPassword = '${uniqueString(resourceGroup().id, serverName)}!Aa1${uniqueString(deployment().name, serverName)}'

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  name: serverName
  location: location
  sku: {
    name: skuName
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: generatedPassword
    version: version

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
