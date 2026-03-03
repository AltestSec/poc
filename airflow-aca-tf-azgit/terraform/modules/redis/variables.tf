variable "name" {
  description = "Redis cache name"
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
  description = "Redis SKU name"
  type        = string
}

variable "family" {
  description = "Redis family"
  type        = string
}

variable "capacity" {
  description = "Redis capacity"
  type        = number
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
