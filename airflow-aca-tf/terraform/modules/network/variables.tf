variable "name" {
  description = "Base name for network resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "firewall_name" {
  description = "Azure Firewall name"
  type        = string
}

variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
}

variable "enable_firewall" {
  description = "Enable Azure Firewall for egress control"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
