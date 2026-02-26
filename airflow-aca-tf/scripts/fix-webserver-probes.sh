#!/bin/bash
set -e

# Fix webserver crashing issue by removing aggressive startup probe
# This script applies the Terraform changes to fix probe configuration

echo "=========================================="
echo "Fixing Webserver Probe Configuration"
echo "=========================================="

cd "$(dirname "$0")/../terraform"

# Check if required environment variables are set
if [ -z "$TF_VAR_postgres_admin_password" ]; then
    echo "Setting default PostgreSQL password..."
    export TF_VAR_postgres_admin_password="AirflowP0c2026!"
fi

if [ -z "$TF_VAR_airflow_fernet_key" ]; then
    echo "Generating Airflow fernet key..."
    export TF_VAR_airflow_fernet_key="$(python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')"
fi

if [ -z "$TF_VAR_airflow_webserver_secret_key" ]; then
    echo "Generating webserver secret key..."
    export TF_VAR_airflow_webserver_secret_key="$(openssl rand -base64 32)"
fi

if [ -z "$TF_VAR_owner" ]; then
    export TF_VAR_owner="oleksandr.merzlikin@nixs.com"
fi

if [ -z "$TF_VAR_duedate" ]; then
    export TF_VAR_duedate="2026-03-10"
fi

echo ""
echo "Changes being applied:"
echo "- Removed startup_probe (was killing container after 30 seconds)"
echo "- Increased readiness_probe failure_count_threshold to 30 (5 minutes)"
echo "- Increased liveness_probe failure_count_threshold to 10 (5 minutes)"
echo ""
echo "This allows webserver 5 minutes to start up before being marked unhealthy."
echo ""

# Show what will change
echo "Running terraform plan..."
terraform plan -var-file=environments/poc/terraform.tfvars -out=tfplan

echo ""
echo "=========================================="
echo "Review the plan above."
echo "To apply changes, run:"
echo "  cd terraform"
echo "  terraform apply tfplan"
echo "=========================================="
