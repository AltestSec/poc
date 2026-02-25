variable "name" {
  description = "PostgreSQL server name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "sku_name" {
  description = "PostgreSQL SKU name"
  type        = string
}

variable "deployment_mode" {
  description = "Deployment mode: poc or production"
  type        = string
}

variable "admin_password" {
  description = "Admin password"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "deployment_mode" {
  type    = string
  default = "dev"
}

variable "sku_name" {
  type = string
  # possible types "B_Standard_B1ms" (burstable) or "GP_Standard_D2s_v3"
}

variable "high_availability_mode" {
  type        = string
  description = "Allowed: SameZone | ZoneRedundant"
  default     = "Disabled"
}
