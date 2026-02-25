terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
  skip_provider_registration = true
}

locals {
  # Prefix for unique resource naming
  # If prefix is provided, use it; otherwise use env_name
  # This allows: prefix-env_name-resource or just env_name-resource
  resource_prefix = var.prefix != "" ? "${var.prefix}-${var.env_name}" : var.env_name
  
  common_tags = {
    owner       = var.owner
    duedate     = var.duedate
    managedwith = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

module "log_analytics" {
  source              = "./modules/log_analytics"
  name                = "${local.resource_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

module "key_vault" {
  source              = "./modules/key_vault"
  name                = "${local.resource_prefix}-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.common_tags
}

module "acr" {
  source              = "./modules/acr"
  name                = replace("${local.resource_prefix}acr", "-", "")
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.acr_sku
  tags                = local.common_tags
}

module "storage" {
  source              = "./modules/storage"
  name                = replace("${local.resource_prefix}stor", "-", "")
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

module "postgresql" {
  source              = "./modules/postgresql"
  name                = "${local.resource_prefix}-pg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.postgres_sku_name
  deployment_mode     = var.deployment_mode
  admin_password      = var.postgres_admin_password
  tags                = local.common_tags
}

module "redis" {
  source              = "./modules/redis"
  name                = "${local.resource_prefix}-redis"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.redis_sku_name
  family              = var.redis_family
  capacity            = var.redis_capacity
  tags                = local.common_tags
}

module "managed_identity" {
  source              = "./modules/managed_identity"
  env_name            = var.env_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

module "aca_environment" {
  source                      = "./modules/aca_environment"
  name                        = "${var.env_name}-env"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  log_analytics_workspace_id  = module.log_analytics.workspace_id
  log_analytics_workspace_key = module.log_analytics.primary_shared_key
  storage_account_name        = module.storage.storage_account_name
  storage_account_key         = module.storage.storage_account_key
  file_share_name             = module.storage.dags_share_name
  tags                        = local.common_tags
}

module "container_apps" {
  source                       = "./modules/container_apps"
  env_name                     = var.env_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  aca_environment_id           = module.aca_environment.environment_id
  aca_storage_name             = module.aca_environment.storage_name
  acr_login_server             = module.acr.login_server
  airflow_image                = var.airflow_image
  etl_runner_image             = var.etl_runner_image
  airflow_fernet_key           = var.airflow_fernet_key
  airflow_webserver_secret_key = var.airflow_webserver_secret_key
  postgres_host                = module.postgresql.fqdn
  postgres_password            = var.postgres_admin_password
  redis_host                   = module.redis.hostname
  redis_primary_key            = module.redis.primary_access_key
  storage_account_name         = module.storage.storage_account_name
  deployment_mode              = var.deployment_mode
  scheduler_identity_id        = module.managed_identity.scheduler_identity_id
  worker_identity_id           = module.managed_identity.worker_identity_id
  webserver_identity_id        = module.managed_identity.webserver_identity_id
  triggerer_identity_id        = module.managed_identity.triggerer_identity_id
  scheduler_principal_id       = module.managed_identity.scheduler_principal_id
  worker_principal_id          = module.managed_identity.worker_principal_id
  storage_account_id           = module.storage.storage_account_id
  tags                         = local.common_tags
}

data "azurerm_client_config" "current" {}
