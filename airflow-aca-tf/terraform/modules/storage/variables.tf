variable "name" {
  description = "Storage account name"
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

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "blob_private_dns_zone_id" {
  description = "Private DNS Zone ID for Blob storage"
  type        = string
}

variable "file_private_dns_zone_id" {
  description = "Private DNS Zone ID for File storage"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
