#!/bin/bash
set -e

# Airflow on Azure Container Apps - Terraform Deployment Script
# Usage: ./deploy.sh <environment> <action>
# Example: ./deploy.sh poc apply

ENVIRONMENT=${1:-poc}
ACTION=${2:-plan}
OWNER=${3:-user@gmail.com}

if [[ ! "$ENVIRONMENT" =~ ^(poc|prod)$ ]]; then
  echo "Error: Environment must be 'poc' or 'prod'"
  exit 1
fi

if [[ ! "$ACTION" =~ ^(plan|apply|destroy)$ ]]; then
  echo "Error: Action must be 'plan', 'apply', or 'destroy'"
  exit 1
fi

echo "=========================================="
echo "Airflow ACA Terraform Deployment"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo "Owner: $OWNER"
echo "=========================================="

# Check required environment variables
if [ -z "$TF_VAR_airflow_fernet_key" ]; then
  echo "Generating Airflow Fernet key..."
  export TF_VAR_airflow_fernet_key=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
  echo "Generated: TF_VAR_airflow_fernet_key"
fi

if [ -z "$TF_VAR_airflow_webserver_secret_key" ]; then
  echo "Generating Airflow webserver secret key..."
  export TF_VAR_airflow_webserver_secret_key=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
  echo "Generated: TF_VAR_airflow_webserver_secret_key"
fi

if [ -z "$TF_VAR_postgres_admin_password" ]; then
  echo "Generating PostgreSQL admin password..."
  export TF_VAR_postgres_admin_password=$(openssl rand -base64 32)
  echo "Generated: TF_VAR_postgres_admin_password"
fi

# Save secrets to file for future use
SECRETS_FILE=".secrets-$ENVIRONMENT.env"
cat > $SECRETS_FILE <<EOF
export TF_VAR_airflow_fernet_key="$TF_VAR_airflow_fernet_key"
export TF_VAR_airflow_webserver_secret_key="$TF_VAR_airflow_webserver_secret_key"
export TF_VAR_postgres_admin_password="$TF_VAR_postgres_admin_password"
EOF
chmod 600 $SECRETS_FILE
echo "Secrets saved to $SECRETS_FILE"

cd terraform

# Initialize Terraform backend
echo "Initializing Terraform..."
terraform init \
  -backend-config="resource_group_name=terraform-state-rg" \
  -backend-config="storage_account_name=tfstateairflow" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=airflow-$ENVIRONMENT.tfstate"

# Execute action
if [ "$ACTION" == "plan" ]; then
  echo "Planning infrastructure..."
  terraform plan \
    -var-file=environments/$ENVIRONMENT/terraform.tfvars \
    -var="owner=$OWNER" \
    -out=tfplan
  
  echo "Plan saved to tfplan"
  echo "To apply: terraform apply tfplan"

elif [ "$ACTION" == "apply" ]; then
  echo "Planning infrastructure..."
  terraform plan \
    -var-file=environments/$ENVIRONMENT/terraform.tfvars \
    -var="owner=$OWNER" \
    -out=tfplan
  
  echo "Applying infrastructure..."
  terraform apply tfplan
  
  echo "=========================================="
  echo "Deployment completed!"
  echo "=========================================="
  
  # Get outputs
  ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
  ACR_NAME=$(echo $ACR_LOGIN_SERVER | cut -d'.' -f1)
  STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
  WEBSERVER_FQDN=$(terraform output -raw webserver_fqdn)
  
  echo "ACR Login Server: $ACR_LOGIN_SERVER"
  echo "Storage Account: $STORAGE_ACCOUNT"
  echo "Webserver FQDN: $WEBSERVER_FQDN"
  echo ""
  
  # Build and push images
  read -p "Build and push images to ACR? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Logging into ACR..."
    az acr login --name $ACR_NAME
    
    echo "Building and pushing Airflow image..."
    cd ../../airflow-aca/airflow
    docker build -t $ACR_LOGIN_SERVER/airflow:latest .
    docker push $ACR_LOGIN_SERVER/airflow:latest
    
    echo "Building and pushing ETL runner image..."
    cd etl-runner
    docker build -t $ACR_LOGIN_SERVER/etl-runner:latest .
    docker push $ACR_LOGIN_SERVER/etl-runner:latest
    
    cd ../../../airflow-aca-tf/terraform
    echo "Images pushed successfully!"
  fi
  
  # Upload DAGs
  read -p "Upload DAGs to storage? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Uploading DAGs..."
    az storage file upload-batch \
      --account-name $STORAGE_ACCOUNT \
      --destination airflow-dags \
      --source ../../airflow-aca/dags
    echo "DAGs uploaded successfully!"
  fi
  
  echo ""
  echo "=========================================="
  echo "Next Steps:"
  echo "=========================================="
  echo "1. Access webserver:"
  echo "   az containerapp tunnel --name ${WEBSERVER_FQDN%%.*} --resource-group airflow-$ENVIRONMENT-rg --port 8080:8080"
  echo ""
  echo "2. Open http://localhost:8080"
  echo ""
  echo "3. Set Airflow Variables in UI:"
  echo "   - AZURE_SUBSCRIPTION_ID"
  echo "   - AZURE_RESOURCE_GROUP"
  echo "   - ACA_ETL_JOB_NAME"
  echo "=========================================="

elif [ "$ACTION" == "destroy" ]; then
  echo "WARNING: This will destroy all infrastructure!"
  read -p "Are you sure? (yes/no) " -r
  echo
  if [[ $REPLY == "yes" ]]; then
    echo "Destroying infrastructure..."
    terraform destroy \
      -var-file=environments/$ENVIRONMENT/terraform.tfvars \
      -var="owner=$OWNER"
    
    echo "Infrastructure destroyed!"
  else
    echo "Destroy cancelled."
  fi
fi

cd ..
