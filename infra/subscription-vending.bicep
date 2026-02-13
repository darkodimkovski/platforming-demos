// ---------------------------------------------------------------------------
// Subscription Vending – creates an isolated subscription per workload
// Uses the Azure Verified Module (AVM) pattern: avm/ptn/lz/sub-vending
// Deployed at management-group scope
// ---------------------------------------------------------------------------
targetScope = 'managementGroup'

// ── Required parameters (supplied from workload spec) ──────────────────────

@description('Workload name – used to derive subscription alias and display name')
param workloadName string

@description('Environment (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for workload resources (passed through for downstream stages)')
param location string

// ── Platform parameters (set by the platform team / pipeline variables) ────

@description('Billing scope for new subscriptions (EA enrollment account or MCA billing profile)')
@secure()
param subscriptionBillingScope string

@description('Management group ID to place the subscription under')
param managementGroupId string

@description('Workload type – Production or DevTest')
@allowed(['Production', 'DevTest'])
param subscriptionWorkload string = 'Production'

@description('Object ID of the team/service principal to grant a role on the subscription (optional)')
param ownerPrincipalId string = ''

@description('Role to grant the owner principal (least-privilege default is Contributor)')
@allowed([
  'Reader'
  'Contributor'
  'Owner'
])
param ownerRole string = 'Contributor'

@description('Optional extra tags to apply at subscription scope (e.g., costCenter, chargeback, dataClassification)')
param additionalSubscriptionTags object = {}

@description('Deployment timestamp (auto-set, do not override)')
param deploymentTimestamp string = utcNow('yyyy-MM-dd')

// ── Derived values ─────────────────────────────────────────────────────────

// Best-effort "slug" to reduce invalid characters in subscription alias/display name.
// (No regex in Bicep; keep it simple and deterministic.)
var workloadSlug = toLower(
  replace(
    replace(
      replace(
        replace(workloadName, ' ', '-'),
      '_', '-'),
    '.', '-'),
  '/', '-')
)

var subscriptionAlias = 'sub-${workloadSlug}-${environment}'
var subscriptionDisplayName = 'sub-${workloadSlug}-${environment}'

var ownerRoleDefinitionMap = {
  Reader: '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
  Contributor: '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'
  Owner: '/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
}

var baseSubscriptionTags = {
  workload: workloadName
  environment: environment
  managedBy: 'platform-pipeline'
  createdAt: deploymentTimestamp
}

var finalSubscriptionTags = union(baseSubscriptionTags, additionalSubscriptionTags)

// ── Subscription Vending via AVM ───────────────────────────────────────────
module subVending 'br/public:avm/ptn/lz/sub-vending:0.4.0' = {
  name: 'vend-${subscriptionAlias}'
  params: {
    // Subscription creation (alias-based vending)
    subscriptionAliasEnabled: true
    subscriptionAliasName: subscriptionAlias
    subscriptionDisplayName: subscriptionDisplayName
    subscriptionBillingScope: subscriptionBillingScope
    subscriptionWorkload: subscriptionWorkload

    // Management group placement (policy/RBAC inheritance boundary)
    subscriptionManagementGroupAssociationEnabled: true
    subscriptionManagementGroupId: managementGroupId

    // Tags for governance, cost chargeback, lifecycle
    subscriptionTags: finalSubscriptionTags

    // Resource provider registration (empty = register defaults only)
    resourceProviders: {}

    // RBAC – grant selected built-in role if principal ID supplied
    roleAssignmentEnabled: !empty(ownerPrincipalId)
    roleAssignments: !empty(ownerPrincipalId)
      ? [
          {
            definition: ownerRoleDefinitionMap[ownerRole]
            principalId: ownerPrincipalId
            relativeScope: ''
          }
        ]
      : []

    // No virtual network for this demo – enable for production landing zones
    virtualNetworkEnabled: false

    // Telemetry
    enableTelemetry: true
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────

@description('The subscription ID of the vended subscription')
output subscriptionId string = subVending.outputs.subscriptionId

@description('The subscription resource ID')
output subscriptionResourceId string = subVending.outputs.subscriptionResourceId

@description('Subscription display name')
output subscriptionName string = subscriptionDisplayName

@description('Subscription alias (stable key for re-runs)')
output subscriptionAlias string = subscriptionAlias

@description('Management group used for association')
output managementGroupIdOut string = managementGroupId

@description('Location for workload resources')
output location string = location
