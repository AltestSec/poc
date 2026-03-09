variable "name" {
  description = "VM name"
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

variable "subnet_id" {
  description = "Subnet ID for VM"
  type        = string
}

variable "vm_size" {
  description = "VM size (use B2s for cheapest option)"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Admin username"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password (must be complex)"
  type        = string
  sensitive   = true
}

variable "allowed_rdp_source_ip" {
  description = "Your public IP address for RDP access (use 'your-ip/32' or '*' for any)"
  type        = string
  default     = "*"
}

variable "managed_identity_id" {
  description = "Managed identity ID for ACR access"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
