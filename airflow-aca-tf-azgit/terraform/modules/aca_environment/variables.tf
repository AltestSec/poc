variable "name" {
  description = "ACA environment name"
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

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
}

variable "log_analytics_workspace_key" {
  description = "Log Analytics workspace key"
  type        = string
  sensitive   = true
}

variable "storage_account_name" {
  description = "Storage account name"
  type        = string
}

variable "storage_account_key" {
  description = "Storage account key"
  type        = string
  sensitive   = true
}

variable "file_share_name" {
  description = "File share name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
