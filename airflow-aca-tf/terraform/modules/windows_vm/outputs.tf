output "vm_id" {
  description = "VM resource ID"
  value       = azurerm_windows_virtual_machine.vm.id
}

output "vm_name" {
  description = "VM name"
  value       = azurerm_windows_virtual_machine.vm.name
}

output "public_ip" {
  description = "VM public IP address for RDP"
  value       = azurerm_public_ip.vm.ip_address
}

output "private_ip" {
  description = "VM private IP address"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "rdp_connection_string" {
  description = "RDP connection string"
  value       = "mstsc /v:${azurerm_public_ip.vm.ip_address}"
}
