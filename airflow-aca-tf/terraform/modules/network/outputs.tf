output "vnet_id" {
  description = "Virtual Network ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual Network name"
  value       = azurerm_virtual_network.main.name
}

output "container_apps_subnet_id" {
  description = "Container Apps subnet ID"
  value       = azurerm_subnet.container_apps.id
}

output "private_endpoints_subnet_id" {
  description = "Private Endpoints subnet ID"
  value       = azurerm_subnet.private_endpoints.id
}

output "postgresql_subnet_id" {
  description = "PostgreSQL subnet ID"
  value       = azurerm_subnet.postgresql.id
}

output "vm_subnet_id" {
  description = "VM subnet ID"
  value       = azurerm_subnet.vm.id
}

output "firewall_private_ip" {
  description = "Azure Firewall private IP address"
  value       = var.enable_firewall ? azurerm_firewall.main[0].ip_configuration[0].private_ip_address : null
}

output "firewall_public_ip" {
  description = "Azure Firewall public IP address"
  value       = var.enable_firewall ? azurerm_public_ip.firewall[0].ip_address : null
}

output "acr_private_dns_zone_id" {
  description = "ACR Private DNS Zone ID"
  value       = azurerm_private_dns_zone.acr.id
}

output "blob_private_dns_zone_id" {
  description = "Blob Private DNS Zone ID"
  value       = azurerm_private_dns_zone.blob.id
}

output "file_private_dns_zone_id" {
  description = "File Private DNS Zone ID"
  value       = azurerm_private_dns_zone.file.id
}

output "postgres_private_dns_zone_id" {
  description = "PostgreSQL Private DNS Zone ID"
  value       = azurerm_private_dns_zone.postgres.id
}
