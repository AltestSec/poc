resource "azapi_resource" "worker" {
  type      = "Microsoft.App/containerApps@2024-03-01"
  name      = "${var.prefix}-wkr"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id

  body = {
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.airflow.id}" = {}
      }
    }

    properties = {
      managedEnvironmentId = azurerm_container_app_environment.cae.id

      configuration = {
        secrets = [
          { name = "redispass", value = azurerm_redis_cache.redis.primary_access_key },
          { name = "safile",    value = azurerm_storage_account.sa.primary_access_key }
        ]
      }

      template = {
        containers = [
          {
            name  = "worker"
            image = var.airflow_image

            resources = {
              cpu    = 0.5
              memory = "1Gi"
            }

            command = ["bash", "-lc"]
            args    = ["airflow celery worker"]

            env = [
              for k, v in local.airflow_base_env : { name = k, value = v }
            ]

            volumeMounts = [
              { volumeName = "dags", mountPath = "/opt/airflow/dags" }
            ]
          }
        ]

        scale = {
          minReplicas = 0
          maxReplicas = 10
          rules = [
            {
              name = "redis-celery-backlog"
              custom = {
                type = "redis"
                metadata = {
                  address              = "${local.redis_host}:${local.redis_port}"
                  listName             = "celery"
                  listLength           = "5"
                  activationListLength = "1"
                }
                auth = [
                  { secretRef = "redispass", triggerParameter = "password" }
                ]
              }
            }
          ]
        }

        volumes = [
          {
            name        = "dags"
            storageType = "AzureFile"
            storageName = azurerm_storage_account.sa.name
            shareName   = azurerm_storage_share.dags.name
            accessKey   = azurerm_storage_account.sa.primary_access_key
          }
        ]
      }
    }
  }
}