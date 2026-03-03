resource "azurerm_user_assigned_identity" "scheduler" {
  name                = "${var.env_name}-scheduler-mi"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "worker" {
  name                = "${var.env_name}-worker-mi"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "webserver" {
  name                = "${var.env_name}-webserver-mi"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "triggerer" {
  name                = "${var.env_name}-triggerer-mi"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
