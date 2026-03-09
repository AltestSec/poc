env_name            = "airflow-poc"
location            = "westeurope"
resource_group_name = "merzlikin-tf-state-rg"
deployment_mode     = "poc"

# Prefix for globally unique resource names (ACR, Storage, Key Vault)
prefix = "merzlikin"

# Enable ETL job (your custom DBT runner)
# Set to false until images are built and pushed to ACR
enable_etl_job = true

# Use images from your ACR (built by pipeline or locally)
# Format: <acr-name>.azurecr.io/<image>:<tag>
# Note: Build and push images first before enabling ETL job
airflow_image    = "merzlikinairflowpocacr.azurecr.io/airflow:latest"
etl_runner_image = "merzlikinairflowpocacr.azurecr.io/etl-runner:latest"

postgres_sku_name = "B_Standard_B1ms"
redis_sku_name    = "Standard"
redis_family      = "C"
redis_capacity    = 1
acr_sku           = "Premium"  # Required for private endpoints

# Optional: Azure Firewall for egress control
# Adds ~$146/month - only enable if you need to restrict outbound traffic
enable_firewall   = false
# firewall_sku_tier = "Basic"  # Uncomment if enable_firewall = true

# Optional: Windows VM for building Docker images and accessing private network
# Adds ~$30-40/month - useful for development
enable_windows_vm     = false
# vm_admin_password     = ""  # Set via TF_VAR_vm_admin_password environment variable
# allowed_rdp_source_ip = "*"  # Change to "your-ip/32" for security
