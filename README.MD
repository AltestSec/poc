# Airflow on Azure Container Apps (PoC) + ACA Jobs

## What you get
- Container Apps Environment (eastus)
- Airflow: webserver (internal), scheduler (always-on), worker (scale-to-zero, KEDA via Redis backlog)
- Managed Postgres Flexible Server (Airflow metadata DB)
- Azure Cache for Redis (Standard) for Celery broker
- Container Apps Job (etl-job) to run ETL containers run-to-completion
- User Assigned Managed Identity (UAMI) + Custom RBAC role to allow `jobs/start`
- Example DAG: start job by ARM API (with per-run template overrides)

## Prereqs
- Terraform >= 1.6
- Azure subscription access (Contributor for initial provisioning)

## Deploy
export TF_VAR_pg_admin_pass="..."
terraform init
terraform apply

## After deploy
- Upload your DAGs into the Azure Files share (or build a custom image with DAGs).
- Airflow UI is internal ingress; access requires private connectivity (VPN/peering/jumpbox).

####################################################################################

RG=$(terraform output -raw resource_group)
SA=$(terraform output -raw storage_account_name)
SHARE=$(terraform output -raw storage_share_name)
SCH=$(terraform output -raw airflow_scheduler_app_name)

./scripts/upload_dags.sh "$RG" "$SA" "$SHARE" "./dags"

# Stop scheduler at night
./scripts/scale_scheduler_office_hours.sh "$RG" "$SCH" off

# Start in the morning
./scripts/scale_scheduler_office_hours.sh "$RG" "$SCH" on