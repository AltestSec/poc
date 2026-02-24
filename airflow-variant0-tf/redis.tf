resource "azurerm_redis_cache" "redis" {
  name                = "${var.prefix}-redis"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  capacity            = 1
  family              = "C"
  sku_name            = "Standard"

  enable_non_ssl_port = true
  redis_configuration {}
}