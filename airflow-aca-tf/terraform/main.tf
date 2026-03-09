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

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

module "network" {
  source              = "./modules/network"
  name                = "${local.resource_prefix}-vnet"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  firewall_name       = "${local.resource_prefix}-fw"
  firewall_sku_tier   = var.firewall_sku_tier
  enable_firewall     = var.enable_firewall
  tags                = local.common_tags
}

module "log_analytics" {
  source              = "./modules/log_analytics"
  name                = "${local.resource_prefix}-logs"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.common_tags
}

module "key_vault" {
  source              = "./modules/key_vault"
  name                = "${local.resource_prefix}-kv"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.common_tags
}

module "acr" {
  source                      = "./modules/acr"
  name                        = replace("${local.resource_prefix}acr", "-", "")
  location                    = data.azurerm_resource_group.main.location
  resource_group_name         = data.azurerm_resource_group.main.name
  sku                         = var.acr_sku
  private_endpoint_subnet_id  = module.network.private_endpoints_subnet_id
  private_dns_zone_id         = module.network.acr_private_dns_zone_id
  tags                        = local.common_tags
}

module "storage" {
  source                      = "./modules/storage"
  name                        = replace("${local.resource_prefix}stor", "-", "")
  location                    = data.azurerm_resource_group.main.location
  resource_group_name         = data.azurerm_resource_group.main.name
  private_endpoint_subnet_id  = module.network.private_endpoints_subnet_id
  blob_private_dns_zone_id    = module.network.blob_private_dns_zone_id
  file_private_dns_zone_id    = module.network.file_private_dns_zone_id
  tags                        = local.common_tags
}

module "postgresql" {
  source              = "./modules/postgresql"
  name                = "${local.resource_prefix}-pg"
  location            = "northeurope"
  resource_group_name = data.azurerm_resource_group.main.name
  sku_name            = var.postgres_sku_name
  deployment_mode     = var.deployment_mode
  admin_password      = var.postgres_admin_password
  delegated_subnet_id = module.network.postgresql_subnet_id
  private_dns_zone_id = module.network.postgres_private_dns_zone_id
  tags                = local.common_tags
}

module "redis" {
  source              = "./modules/redis"
  name                = "${local.resource_prefix}-redis"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku_name            = var.redis_sku_name
  family              = var.redis_family
  capacity            = var.redis_capacity
  tags                = local.common_tags
}

module "managed_identity" {
  source              = "./modules/managed_identity"
  env_name            = var.env_name
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.common_tags
}

module "aca_environment" {
  source                      = "./modules/aca_environment"
  name                        = "${var.env_name}-env"
  location                    = data.azurerm_resource_group.main.location
  resource_group_name         = data.azurerm_resource_group.main.name
  log_analytics_workspace_id  = module.log_analytics.workspace_id
  log_analytics_workspace_key = module.log_analytics.primary_shared_key
  storage_account_name        = module.storage.storage_account_name
  storage_account_key         = module.storage.storage_account_key
  file_share_name             = module.storage.dags_share_name
  infrastructure_subnet_id    = module.network.container_apps_subnet_id
  tags                        = local.common_tags
}

module "container_apps" {
  source                       = "./modules/container_apps"
  env_name                     = var.env_name
  location                     = data.azurerm_resource_group.main.location
  resource_group_name          = data.azurerm_resource_group.main.name
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
  enable_etl_job               = var.enable_etl_job
  scheduler_identity_id        = module.managed_identity.scheduler_identity_id
  worker_identity_id           = module.managed_identity.worker_identity_id
  webserver_identity_id        = module.managed_identity.webserver_identity_id
  triggerer_identity_id        = module.managed_identity.triggerer_identity_id
  scheduler_principal_id       = module.managed_identity.scheduler_principal_id
  worker_principal_id          = module.managed_identity.worker_principal_id
  storage_account_id           = module.storage.storage_account_id
  tags                         = local.common_tags
}

# Optional Windows VM for accessing private network
module "windows_vm" {
  count                   = var.enable_windows_vm ? 1 : 0
  source                  = "./modules/windows_vm"
  name                    = "${local.resource_prefix}-vm"
  resource_group_name     = data.azurerm_resource_group.main.name
  location                = data.azurerm_resource_group.main.location
  subnet_id               = module.network.vm_subnet_id
  vm_size                 = var.vm_size
  admin_username          = var.vm_admin_username
  admin_password          = var.vm_admin_password
  allowed_rdp_source_ip   = var.allowed_rdp_source_ip
  managed_identity_id     = module.managed_identity.scheduler_identity_id
  tags                    = local.common_tags
}
