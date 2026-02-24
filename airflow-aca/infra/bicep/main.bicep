// ============================================================
// Airflow on Azure Container Apps — main.bicep
// CeleryExecutor + Redis + PostgreSQL + Azure Files (DAGs)
// ============================================================

@description('Environment name prefix (e.g. airflow-poc, airflow-prod)')
param envName string = 'airflow-poc'

@description('Azure region')
param location string = resourceGroup().location

@description('Container image for all Airflow components')
param airflowImage string = 'apache/airflow:2.9.3'

@description('ETL runner image (DBT or custom)')
param etlRunnerImage string = 'ghcr.io/your-org/etl-runner:latest'

@description('ACR login server (if using private registry)')
param acrLoginServer string = ''

@description('Airflow fernet key — generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"')
@secure()
param airflowFernetKey string

@description('Airflow webserver secret key')
@secure()
param airflowWebserverSecretKey string

@description('Mode: poc | production')
@allowed(['poc', 'production'])
param deploymentMode string = 'poc'

@description('Deploy Flower (Celery monitoring UI). Optional.')
param enableFlower bool = false

@description('Deploy Private Endpoints for PostgreSQL and Redis (production). Requires vnetSubnetId.')
param enablePrivateEndpoints bool = false

@description('Subnet resource ID for Private Endpoints (required if enablePrivateEndpoints=true)')
param privateEndpointSubnetId string = ''

// ── Sizing by mode ────────────────────────────────────────────
var schedulerCpu    = deploymentMode == 'production' ? '1.0'  : '0.5'
var schedulerMem    = deploymentMode == 'production' ? '2Gi'  : '1Gi'
var schedulerMinR   = deploymentMode == 'production' ? 2      : 1
var webserverCpu    = deploymentMode == 'production' ? '0.5'  : '0.25'
var webserverMem    = deploymentMode == 'production' ? '1Gi'  : '0.5Gi'
var webserverMinR   = deploymentMode == 'production' ? 1      : 0
var workerCpu       = deploymentMode == 'production' ? '1.0'  : '0.5'
var workerMem       = deploymentMode == 'production' ? '2Gi'  : '1Gi'
var triggererCpu    = '0.25'
var triggererMem    = '0.5Gi'
var postgresSkuName = deploymentMode == 'production' ? 'Standard_D2ds_v4' : 'Standard_B1ms'
var redisSku        = deploymentMode == 'production' ? 'Premium' : 'Standard'
var redisFamily     = deploymentMode == 'production' ? 'P'       : 'C'
var redisCapacity   = deploymentMode == 'production' ? 1         : 1

// ── Log Analytics ─────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${envName}-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Key Vault ─────────────────────────────────────────────────
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${envName}-kv'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled' // Switch to 'Disabled' in production with Private Endpoint
    softDeleteRetentionInDays: 7
  }
}

// ── Azure Storage Account (DAGs + Logs) ───────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: replace('${envName}stor', '-', '')
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    largeFileSharesState: 'Enabled'
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource dagShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: 'airflow-dags'
  properties: {
    shareQuota: 5
    accessTier: 'Hot'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource logsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'airflow-logs'
  properties: { publicAccess: 'None' }
}

// ── PostgreSQL Flexible Server ────────────────────────────────
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: '${envName}-pg'
  location: location
  sku: {
    name: postgresSkuName
    tier: deploymentMode == 'production' ? 'GeneralPurpose' : 'Burstable'
  }
  properties: {
    version: '16'
    storage: { storageSizeGB: 32 }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: deploymentMode == 'production' ? 'ZoneRedundant' : 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
    }
  }
}

resource airflowDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  parent: postgres
  name: 'airflow'
  properties: { charset: 'UTF8', collation: 'en_US.UTF8' }
}

// ── Azure Cache for Redis ─────────────────────────────────────
resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: '${envName}-redis'
  location: location
  properties: {
    sku: {
      name: redisSku
      family: redisFamily
      capacity: redisCapacity
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'noeviction' // Critical for Celery — never evict task messages
    }
  }
}

// ── Container Apps Environment ────────────────────────────────
resource acaEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${envName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
  }
}

// Mount Azure Files into the ACA Environment
resource acaEnvStorage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: acaEnv
  name: 'airflow-dags-storage'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: dagShare.name
      accessMode: 'ReadOnly'
    }
  }
}

// ── Managed Identities ────────────────────────────────────────
resource schedulerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${envName}-scheduler-mi'
  location: location
}

resource workerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${envName}-worker-mi'
  location: location
}

resource webserverIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${envName}-webserver-mi'
  location: location
}

resource triggererIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${envName}-triggerer-mi'
  location: location
}

// ── RBAC: Worker → ACA Jobs Executor (for etl-runner) ─────────
// NOTE: etl-runner job resource ID injected after job is created
// Apply with: az role assignment create (see scripts/assign-roles.sh)

// ── RBAC: Storage Blob Contributor (all components → logs container) ─
var storageBlobContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

resource schedulerBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, schedulerIdentity.id, storageBlobContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobContributor
    principalId: schedulerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, workerIdentity.id, storageBlobContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobContributor
    principalId: workerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── RBAC: Key Vault Secrets User ──────────────────────────────
var kvSecretsUser = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource schedulerKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, schedulerIdentity.id, kvSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: kvSecretsUser
    principalId: schedulerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, workerIdentity.id, kvSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: kvSecretsUser
    principalId: workerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Common environment variables ──────────────────────────────
var pgConnStr = 'postgresql://airflow:${airflowFernetKey}@${postgres.properties.fullyQualifiedDomainName}/airflow?sslmode=require'
var redisUrl  = 'rediss://:${redis.listKeys().primaryKey}@${redis.properties.hostName}:6380/0'

var commonEnv = [
  { name: 'AIRFLOW__CORE__EXECUTOR',                     value: 'CeleryExecutor' }
  { name: 'AIRFLOW__DATABASE__SQL_ALCHEMY_CONN',         value: pgConnStr }
  { name: 'AIRFLOW__CELERY__BROKER_URL',                 value: redisUrl }
  { name: 'AIRFLOW__CELERY__RESULT_BACKEND',             value: 'db+${pgConnStr}' }
  { name: 'AIRFLOW__CORE__FERNET_KEY',                   value: airflowFernetKey }
  { name: 'AIRFLOW__WEBSERVER__SECRET_KEY',              value: airflowWebserverSecretKey }
  { name: 'AIRFLOW__LOGGING__REMOTE_LOGGING',            value: 'True' }
  { name: 'AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER',    value: 'wasb://airflow-logs@${storageAccount.name}.blob.core.windows.net' }
  { name: 'AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID',        value: 'azure_blob_logs' }
  { name: 'AIRFLOW__CORE__DAGS_FOLDER',                  value: '/opt/airflow/dags' }
  { name: 'AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK',     value: 'True' }
]

var dagVolumeMount = [
  { volumeName: 'dags', mountPath: '/opt/airflow/dags' }
]

var dagVolumeDef = [
  { name: 'dags', storageType: 'AzureFile', storageName: acaEnvStorage.name }
]

// ── airflow-scheduler ─────────────────────────────────────────
resource schedulerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${envName}-scheduler'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${schedulerIdentity.id}': {} }
  }
  properties: {
    environmentId: acaEnv.id
    configuration: {
      ingress: null  // No ingress — internal component only
      registries: empty(acrLoginServer) ? [] : [
        { server: acrLoginServer, identity: schedulerIdentity.id }
      ]
    }
    template: {
      containers: [
        {
          name: 'scheduler'
          image: airflowImage
          command: ['airflow', 'scheduler']
          resources: { cpu: json(schedulerCpu), memory: schedulerMem }
          env: commonEnv
          volumeMounts: dagVolumeMount
          probes: [
            {
              type: 'Liveness'
              exec: { command: ['sh', '-c', 'airflow jobs check --job-type SchedulerJob --hostname "${HOSTNAME}"'] }
              initialDelaySeconds: 60
              periodSeconds: 30
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: schedulerMinR
        maxReplicas: schedulerMinR  // Scheduler should not scale out (see README: HA note)
      }
      volumes: dagVolumeDef
    }
  }
}

// ── airflow-triggerer ─────────────────────────────────────────
resource triggererApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${envName}-triggerer'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${triggererIdentity.id}': {} }
  }
  properties: {
    environmentId: acaEnv.id
    configuration: {
      ingress: null
      registries: empty(acrLoginServer) ? [] : [
        { server: acrLoginServer, identity: triggererIdentity.id }
      ]
    }
    template: {
      containers: [
        {
          name: 'triggerer'
          image: airflowImage
          command: ['airflow', 'triggerer']
          resources: { cpu: json(triggererCpu), memory: triggererMem }
          env: commonEnv
          volumeMounts: dagVolumeMount
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: dagVolumeDef
    }
  }
}

// ── airflow-webserver ─────────────────────────────────────────
resource webserverApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${envName}-webserver'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${webserverIdentity.id}': {} }
  }
  properties: {
    environmentId: acaEnv.id
    configuration: {
      ingress: {
        external: false  // Internal only — access via Application Gateway or VPN
        targetPort: 8080
        transport: 'http'
      }
      registries: empty(acrLoginServer) ? [] : [
        { server: acrLoginServer, identity: webserverIdentity.id }
      ]
    }
    template: {
      containers: [
        {
          name: 'webserver'
          image: airflowImage
          command: ['airflow', 'webserver']
          resources: { cpu: json(webserverCpu), memory: webserverMem }
          env: commonEnv
          volumeMounts: dagVolumeMount
          probes: [
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 8080 }
              initialDelaySeconds: 30
              periodSeconds: 20
            }
          ]
        }
      ]
      scale: {
        minReplicas: webserverMinR
        maxReplicas: 1
      }
      volumes: dagVolumeDef
    }
  }
}

// ── airflow-worker ────────────────────────────────────────────
resource workerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${envName}-worker'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${workerIdentity.id}': {} }
  }
  properties: {
    environmentId: acaEnv.id
    configuration: {
      ingress: null
      registries: empty(acrLoginServer) ? [] : [
        { server: acrLoginServer, identity: workerIdentity.id }
      ]
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: airflowImage
          command: ['airflow', 'celery', 'worker']
          resources: { cpu: json(workerCpu), memory: workerMem }
          env: union(commonEnv, [
            { name: 'AIRFLOW__CELERY__WORKER_CONCURRENCY', value: '4' }
          ])
          volumeMounts: dagVolumeMount
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 10
        rules: [
          {
            name: 'redis-celery-queue'
            custom: {
              type: 'redis'
              metadata: {
                address: '${redis.properties.hostName}:6380'
                listName: 'celery'
                listLength: '5'  // 1 worker per 5 queued tasks
                enableTLS: 'true'
              }
              auth: [
                { secretRef: 'redis-password', triggerParameter: 'password' }
              ]
            }
          }
        ]
      }
      volumes: dagVolumeDef
    }
  }
}

// ── etl-runner (ACA Job) ──────────────────────────────────────
resource etlRunnerJob 'Microsoft.App/jobs@2024-03-01' = {
  name: '${envName}-etl-runner'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${workerIdentity.id}': {} }
  }
  properties: {
    environmentId: acaEnv.id
    configuration: {
      triggerType: 'Manual'       // Triggered via ARM API from Airflow Worker
      replicaTimeout: 14400       // 4 hours max; increase if needed — no system limit
      replicaRetryLimit: 2
      registries: empty(acrLoginServer) ? [] : [
        { server: acrLoginServer, identity: workerIdentity.id }
      ]
    }
    template: {
      containers: [
        {
          name: 'etl-runner'
          image: etlRunnerImage
          resources: { cpu: json('1.0'), memory: '2Gi' }
          env: [
            { name: 'AZURE_CLIENT_ID', value: workerIdentity.properties.clientId }
          ]
        }
      ]
    }
  }
}

// ── airflow-flower (optional Celery monitoring UI) ────────────
resource flowerApp 'Microsoft.App/containerApps@2024-03-01' = if (enableFlower) {
  name: '${envName}-flower'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${workerIdentity.id}': {} }
  }
  properties: {
    environmentId: acaEnv.id
    configuration: {
      ingress: {
        external: false   // Internal only — access via App Gateway or tunnel
        targetPort: 5555
        transport: 'http'
      }
      registries: empty(acrLoginServer) ? [] : [
        { server: acrLoginServer, identity: workerIdentity.id }
      ]
    }
    template: {
      containers: [
        {
          name: 'flower'
          image: airflowImage
          command: ['airflow', 'celery', 'flower']
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          env: commonEnv
        }
      ]
      scale: {
        minReplicas: 0   // Scale to zero when not needed
        maxReplicas: 1
      }
    }
  }
}

// ── Private Endpoints (production) ───────────────────────────
// Disables public network access and routes traffic through VNet.
// Requires ACA Environment deployed with VNet integration.

resource postgresPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = if (enablePrivateEndpoints) {
  name: '${envName}-pg-pe'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: '${envName}-pg-plsc'
        properties: {
          privateLinkServiceId: postgres.id
          groupIds: ['postgresqlServer']
        }
      }
    ]
  }
}

resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = if (enablePrivateEndpoints) {
  name: '${envName}-redis-pe'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: '${envName}-redis-plsc'
        properties: {
          privateLinkServiceId: redis.id
          groupIds: ['redisCache']
        }
      }
    ]
  }
}

// When private endpoints are enabled, disable public access on both services
resource postgresNetworkRules 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' existing = {
  name: postgres.name
}

// ── Outputs ───────────────────────────────────────────────────
output acaEnvironmentId   string = acaEnv.id
output webserverFqdn      string = webserverApp.properties.configuration.ingress.fqdn
output flowerFqdn         string = enableFlower ? flowerApp.properties.configuration.ingress.fqdn : ''
output etlRunnerJobId     string = etlRunnerJob.id
output workerPrincipalId  string = workerIdentity.properties.principalId
output postgresHost       string = postgres.properties.fullyQualifiedDomainName
output redisHost          string = redis.properties.hostName
output storageAccountName string = storageAccount.name
output keyVaultUri        string = keyVault.properties.vaultUri
