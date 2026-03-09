# Virtual Network for private infrastructure
resource "azurerm_virtual_network" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.0.0.0/16"]

  tags = var.tags
}

# Subnet for Azure Firewall
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Subnet for Azure Firewall Management
resource "azurerm_subnet" "firewall_management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Subnet for Container Apps (delegated)
resource "azurerm_subnet" "container_apps" {
  name                 = "AzureContainerAppSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/23"]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Subnet for Private Endpoints
resource "azurerm_subnet" "private_endpoints" {
  name                 = "PrivateEndpointSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.4.0/24"]
}

# Subnet for PostgreSQL (delegated)
resource "azurerm_subnet" "postgresql" {
  name                 = "PostgreSQLSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.5.0/24"]

  delegation {
    name = "Microsoft.DBforPostgreSQL.flexibleServers"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Subnet for Jump Box VM
resource "azurerm_subnet" "vm" {
  name                 = "VMSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.6.0/24"]
}

# ============================================================
# OPTIONAL: Azure Firewall for Egress Control
# Only deploy if enable_firewall = true
# Saves ~$146-912/month when disabled
# ============================================================

# Public IP for Azure Firewall
resource "azurerm_public_ip" "firewall" {
  count               = var.enable_firewall ? 1 : 0
  name                = "${var.name}-fw-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Public IP for Azure Firewall Management
resource "azurerm_public_ip" "firewall_management" {
  count               = var.enable_firewall ? 1 : 0
  name                = "${var.name}-fw-mgmt-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Azure Firewall
resource "azurerm_firewall" "main" {
  count               = var.enable_firewall ? 1 : 0
  name                = var.firewall_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  dns_proxy_enabled   = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  management_ip_configuration {
    name                 = "management"
    subnet_id            = azurerm_subnet.firewall_management.id
    public_ip_address_id = azurerm_public_ip.firewall_management[0].id
  }

  tags = var.tags
}

# Firewall Policy
resource "azurerm_firewall_policy" "main" {
  count               = var.enable_firewall ? 1 : 0
  name                = "${var.name}-fw-policy"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.firewall_sku_tier

  dns {
    proxy_enabled = true
  }

  tags = var.tags
}

# Firewall Policy Rule Collection Group
resource "azurerm_firewall_policy_rule_collection_group" "main" {
  count              = var.enable_firewall ? 1 : 0
  name               = "DefaultRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.main[0].id
  priority           = 200

  application_rule_collection {
    name     = "AllowMicrosoftServices"
    priority = 200
    action   = "Allow"

    rule {
      name = "AllowACR"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = ["10.0.2.0/23"]
      destination_fqdns = [
        "*.azurecr.io",
        "*.blob.core.windows.net",
        "mcr.microsoft.com",
        "*.data.mcr.microsoft.com"
      ]
    }

    rule {
      name = "AllowAzureServices"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = ["10.0.2.0/23"]
      destination_fqdns = [
        "*.azure.com",
        "*.microsoft.com",
        "*.windows.net",
        "*.azure-api.net"
      ]
    }

    rule {
      name = "AllowPyPI"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = ["10.0.2.0/23"]
      destination_fqdns = [
        "pypi.org",
        "*.pypi.org",
        "files.pythonhosted.org"
      ]
    }
  }

  application_rule_collection {
    name     = "AllowAirflowDependencies"
    priority = 201
    action   = "Allow"

    rule {
      name = "AllowPackageManagers"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = ["10.0.2.0/23"]
      destination_fqdns = [
        "*.ubuntu.com",
        "*.debian.org",
        "security.ubuntu.com",
        "archive.ubuntu.com"
      ]
    }
  }

  network_rule_collection {
    name     = "AllowDNS"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "AllowDNSTraffic"
      protocols             = ["UDP"]
      source_addresses      = ["10.0.2.0/23"]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }
  }
}

# Route Table for Container Apps (only with firewall)
resource "azurerm_route_table" "container_apps" {
  count               = var.enable_firewall ? 1 : 0
  name                = "${var.name}-aca-rt"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# Default route to Firewall
resource "azurerm_route" "firewall_route" {
  count                  = var.enable_firewall ? 1 : 0
  name                   = "firewall-route"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.container_apps[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.main[0].ip_configuration[0].private_ip_address
}

# Internet route for Firewall public IP
resource "azurerm_route" "internet_route" {
  count               = var.enable_firewall ? 1 : 0
  name                = "internet-route"
  resource_group_name = var.resource_group_name
  route_table_name    = azurerm_route_table.container_apps[0].name
  address_prefix      = "${azurerm_public_ip.firewall[0].ip_address}/32"
  next_hop_type       = "Internet"
}

# Associate Route Table with Container Apps Subnet
resource "azurerm_subnet_route_table_association" "container_apps" {
  count          = var.enable_firewall ? 1 : 0
  subnet_id      = azurerm_subnet.container_apps.id
  route_table_id = azurerm_route_table.container_apps[0].id
}

# Private DNS Zone for ACR
resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Private DNS Zone for Blob Storage
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Private DNS Zone for File Storage
resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Link Private DNS Zones to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "${var.name}-acr-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.main.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "${var.name}-blob-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.main.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "${var.name}-file-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = azurerm_virtual_network.main.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.name}-postgres-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id

  tags = var.tags
}
