output "id" {
  description = "Redis cache ID"
  value       = azurerm_redis_cache.redis.id
}

output "hostname" {
  description = "Redis hostname"
  value       = azurerm_redis_cache.redis.hostname
}

output "primary_access_key" {
  description = "Redis primary access key"
  value       = azurerm_redis_cache.redis.primary_access_key
  sensitive   = true
}

output "ssl_port" {
  description = "Redis SSL port"
  value       = azurerm_redis_cache.redis.ssl_port
}
