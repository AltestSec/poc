# Secure Deployment Checklist

Complete checklist for deploying Airflow on Azure Container Apps with private networking and security controls.

## Pre-Deployment

### Azure Subscription Setup

- [ ] Azure subscription with appropriate permissions
- [ ] Resource providers registered:
  ```bash
  az provider register --namespace Microsoft.App
  az provider register --namespace Microsoft.ContainerRegistry
  az provider register --namespace Microsoft.Storage
  az provider register --namespace Microsoft.DBforPostgreSQL
  az provider register --namespace Microsoft.Cache
  az provider register --namespace Microsoft.KeyVault
  az provider register --namespace Microsoft.OperationalInsights
  az provider register --namespace Microsoft.ManagedIdentity
  az provider register --namespace Microsoft.Network
  ```

### Resource Group

- [ ] Resource group created manually:
  ```bash
  az group create \
    --name <resource-group-name> \
    --location westeurope
  ```

### Terraform Backend

- [ ] Storage account for Terraform state created
- [ ] Container for state files created
- [ ] Service Principal has Storage Blob Data Contributor role

### Secrets Generation

- [ ] Airflow Fernet key generated:
  ```bash
  python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
  ```
- [ ] Airflow webserver secret key generated:
  ```bash
  python3 -c "import secrets; print(secrets.token_urlsafe(32))"
  ```
- [ ] PostgreSQL admin password generated:
  ```bash
  openssl rand -base64 32
  ```

## Network Configuration

### Virtual Network

- [ ] VNet created with address space 10.0.0.0/16
- [ ] Azure Firewall subnet (10.0.0.0/24) created
- [ ] Firewall Management subnet (10.0.1.0/24) created
- [ ] Container Apps subnet (10.0.2.0/23) created with delegation
- [ ] Private Endpoints subnet (10.0.4.0/24) created
- [ ] PostgreSQL subnet (10.0.5.0/24) created with delegation

### Azure Firewall

- [ ] Firewall deployed (Basic or Standard tier)
- [ ] Public IPs assigned
- [ ] DNS proxy enabled
- [ ] Application rules configured:
  - [ ] Azure services (ACR, Storage, Azure APIs)
  - [ ] Package managers (PyPI, Ubuntu)
- [ ] Network rules configured:
  - [ ] DNS (UDP 53)
- [ ] Diagnostic settings enabled

### User Defined Routes

- [ ] Route table created
- [ ] Default route (0.0.0.0/0) to Firewall
- [ ] Internet route for Firewall public IP
- [ ] Route table associated with Container Apps subnet

### Private DNS Zones

- [ ] `privatelink.azurecr.io` created and linked to VNet
- [ ] `privatelink.blob.core.windows.net` created and linked to VNet
- [ ] `privatelink.file.core.windows.net` created and linked to VNet
- [ ] `privatelink.postgres.database.azure.com` created and linked to VNet

## Service Configuration

### Azure Container Registry

- [ ] ACR created with Premium SKU
- [ ] Public network access disabled
- [ ] Admin account disabled
- [ ] Private endpoint created in Private Endpoints subnet
- [ ] Private DNS zone group configured
- [ ] Managed identity has AcrPull role

### Storage Account

- [ ] Storage account created
- [ ] Public network access disabled
- [ ] Network rules: default deny, bypass Azure Services
- [ ] HTTPS only enabled
- [ ] TLS 1.2 minimum
- [ ] Blob private endpoint created
- [ ] File private endpoint created
- [ ] Private DNS zone groups configured
- [ ] File share created for DAGs
- [ ] Blob container created for logs

### PostgreSQL Flexible Server

- [ ] PostgreSQL server created in delegated subnet
- [ ] Public network access disabled
- [ ] Private DNS zone configured
- [ ] No firewall rules (private network only)
- [ ] Airflow database created
- [ ] Backup retention configured (7 days minimum)

### Redis Cache

- [ ] Redis instance created
- [ ] TLS enabled (port 6380)
- [ ] Appropriate SKU selected (Standard for PoC, Premium for Prod)

### Key Vault

- [ ] Key Vault created
- [ ] Secrets stored:
  - [ ] Airflow Fernet key
  - [ ] Airflow webserver secret key
  - [ ] PostgreSQL password
- [ ] Managed identities have Secret Get permissions

### Log Analytics

- [ ] Workspace created
- [ ] Retention period configured
- [ ] Diagnostic settings configured for:
  - [ ] Azure Firewall
  - [ ] Container Apps Environment
  - [ ] Container Apps

## Container Apps Configuration

### Managed Identities

- [ ] Scheduler identity created
- [ ] Worker identity created
- [ ] Webserver identity created
- [ ] Triggerer identity created

### RBAC Assignments

- [ ] All identities have Contributor role on resource group
- [ ] All identities have AcrPull role on ACR
- [ ] All identities have Storage Blob Data Contributor on storage
- [ ] All identities have Key Vault Secrets User on Key Vault

### Container Apps Environment

- [ ] Environment created in Container Apps subnet
- [ ] Internal load balancer enabled
- [ ] Log Analytics configured
- [ ] Storage mount configured for DAGs

### Container Apps

- [ ] Scheduler deployed:
  - [ ] Managed identity assigned
  - [ ] ACR registry configured
  - [ ] Environment variables set
  - [ ] DAGs volume mounted
  - [ ] Health probes configured
- [ ] Webserver deployed:
  - [ ] Ingress enabled (internal only)
  - [ ] Health probes configured
  - [ ] Appropriate replicas
- [ ] Worker deployed:
  - [ ] Auto-scaling configured (0-10)
  - [ ] Celery concurrency set
- [ ] Triggerer deployed:
  - [ ] Single replica

### ETL Runner Job

- [ ] Job created
- [ ] Managed identity assigned
- [ ] Manual trigger configured
- [ ] Timeout set (4 hours)
- [ ] Retry limit configured

## Container Images

### Build Images

- [ ] Airflow image built:
  ```bash
  cd docker/airflow
  docker build -t <acr>.azurecr.io/airflow:latest .
  ```
- [ ] ETL runner image built:
  ```bash
  cd docker/etl-runner
  docker build -t <acr>.azurecr.io/etl-runner:latest .
  ```

### Push to ACR

- [ ] Logged into ACR:
  ```bash
  az acr login --name <acr-name>
  ```
- [ ] Airflow image pushed
- [ ] ETL runner image pushed

### Update Container Apps

- [ ] Container Apps updated with new image tags
- [ ] Revisions activated

## DAGs Deployment

- [ ] DAGs uploaded to file share:
  ```bash
  az storage file upload-batch \
    --account-name <storage-account> \
    --destination airflow-dags \
    --source ./dags
  ```
- [ ] Test DAG deployed
- [ ] Production DAGs deployed

## Security Testing

### Network Security Tests

- [ ] ETL job test executed:
  ```bash
  ./scripts/test-etl-job.sh <resource-group> <env-name>
  ```
- [ ] Allowed endpoints accessible (PyPI, Azure services)
- [ ] Blocked endpoints denied (Google, social media)
- [ ] Firewall logs reviewed

### Access Control Tests

- [ ] Webserver accessible only via internal network
- [ ] ACR accessible only via private endpoint
- [ ] Storage accessible only via private endpoint
- [ ] PostgreSQL accessible only via private network
- [ ] No public IPs on services (except Firewall)

### Authentication Tests

- [ ] Managed identity authentication to ACR works
- [ ] Managed identity authentication to Storage works
- [ ] Managed identity authentication to Key Vault works
- [ ] PostgreSQL authentication works

## Operational Readiness

### Monitoring

- [ ] Log Analytics queries configured
- [ ] Firewall logs monitored
- [ ] Container Apps logs monitored
- [ ] Alerts configured for:
  - [ ] Failed container starts
  - [ ] High firewall denials
  - [ ] Storage access failures
  - [ ] Database connection failures

### Backup and Recovery

- [ ] PostgreSQL backups enabled
- [ ] DAGs backed up to separate location
- [ ] Terraform state backed up
- [ ] Recovery procedures documented

### Documentation

- [ ] Architecture diagram updated
- [ ] Network diagram created
- [ ] Runbook created
- [ ] Troubleshooting guide updated
- [ ] Security controls documented

## Post-Deployment Validation

### Functional Tests

- [ ] Airflow webserver accessible
- [ ] Scheduler running and processing DAGs
- [ ] Workers executing tasks
- [ ] Triggerer handling deferred tasks
- [ ] ETL jobs executing successfully
- [ ] Logs being written to blob storage

### Performance Tests

- [ ] DAG execution times acceptable
- [ ] Worker auto-scaling working
- [ ] Database performance adequate
- [ ] Redis performance adequate

### Security Validation

- [ ] Penetration testing completed (if required)
- [ ] Security scan of container images
- [ ] Compliance requirements met
- [ ] Security review completed

## Cleanup (For Testing)

If you need to tear down the environment:

- [ ] Stop all Container Apps
- [ ] Delete Container Apps
- [ ] Delete Container Apps Environment
- [ ] Delete Private Endpoints
- [ ] Delete Firewall
- [ ] Delete Route Table
- [ ] Delete VNet
- [ ] Delete Storage Account
- [ ] Delete PostgreSQL Server
- [ ] Delete Redis Cache
- [ ] Delete ACR
- [ ] Delete Key Vault
- [ ] Delete Log Analytics Workspace
- [ ] Delete Managed Identities
- [ ] Delete Resource Group (if desired)

Or use Terraform:
```bash
terraform destroy -var-file=environments/poc/terraform.tfvars
```

## Sign-Off

- [ ] Technical lead approval
- [ ] Security team approval
- [ ] Operations team handoff complete
- [ ] Documentation complete
- [ ] Training completed

## Notes

- Deployment date: _______________
- Deployed by: _______________
- Environment: [ ] PoC [ ] Production
- Issues encountered: _______________
- Lessons learned: _______________
