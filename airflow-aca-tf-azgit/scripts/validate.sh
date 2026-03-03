#!/bin/bash
# ============================================================
# validate.sh - Validate Terraform and Docker configurations
# ============================================================
set -e

echo "=========================================="
echo "Validation Script"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Project root: $PROJECT_ROOT"
echo ""

# Check 1: Terraform files exist
echo "✓ Checking Terraform files..."
REQUIRED_TF_FILES=(
  "terraform/main.tf"
  "terraform/variables.tf"
  "terraform/outputs.tf"
  "terraform/environments/poc/terraform.tfvars"
)

for file in "${REQUIRED_TF_FILES[@]}"; do
  if [ -f "$PROJECT_ROOT/$file" ]; then
    echo "  ✅ $file"
  else
    echo -e "  ${RED}❌ $file not found${NC}"
    exit 1
  fi
done
echo ""

# Check 2: Docker files exist
echo "✓ Checking Docker files..."
REQUIRED_DOCKER_FILES=(
  "docker/airflow/Dockerfile"
  "docker/airflow/config/webserver_config.py"
  "docker/airflow/plugins/aca_job_operator.py"
  "docker/etl-runner/Dockerfile"
  "docker/etl-runner/entrypoint.sh"
  "docker/etl-runner/profiles.yml"
  "docker/etl-runner/dbt_project/dbt_project.yml"
)

for file in "${REQUIRED_DOCKER_FILES[@]}"; do
  if [ -f "$PROJECT_ROOT/$file" ]; then
    echo "  ✅ $file"
  else
    echo -e "  ${RED}❌ $file not found${NC}"
    exit 1
  fi
done
echo ""

# Check 3: Terraform format
echo "✓ Checking Terraform format..."
if terraform fmt -check -recursive "$PROJECT_ROOT/terraform" > /dev/null 2>&1; then
  echo "  ✅ Terraform files are properly formatted"
else
  echo -e "  ${YELLOW}⚠️  Terraform files need formatting. Run: terraform fmt -recursive${NC}"
fi
echo ""

# Check 4: Pipeline file exists
echo "✓ Checking pipeline configuration..."
if [ -f "$PROJECT_ROOT/pipelines/azure-pipelines.yml" ]; then
  echo "  ✅ azure-pipelines.yml exists"
  
  # Check if pipeline references correct docker paths
  if grep -q "airflow-aca-tf/docker/airflow" "$PROJECT_ROOT/pipelines/azure-pipelines.yml"; then
    echo "  ✅ Pipeline references correct docker paths"
  else
    echo -e "  ${RED}❌ Pipeline references incorrect docker paths${NC}"
    exit 1
  fi
else
  echo -e "  ${RED}❌ azure-pipelines.yml not found${NC}"
  exit 1
fi
echo ""

# Check 5: Documentation files
echo "✓ Checking documentation..."
REQUIRED_DOCS=(
  "README.md"
  "RBAC_COMMANDS.md"
  "RBAC_SETUP.md"
  "QUICK_REFERENCE.md"
  "docker/README.md"
)

for file in "${REQUIRED_DOCS[@]}"; do
  if [ -f "$PROJECT_ROOT/$file" ]; then
    echo "  ✅ $file"
  else
    echo -e "  ${YELLOW}⚠️  $file not found${NC}"
  fi
done
echo ""

# Check 6: Verify tfvars configuration
echo "✓ Checking tfvars configuration..."
TFVARS="$PROJECT_ROOT/terraform/environments/poc/terraform.tfvars"

if grep -q "prefix = \"merzlikin\"" "$TFVARS"; then
  echo "  ✅ Prefix is set correctly"
else
  echo -e "  ${RED}❌ Prefix not set in tfvars${NC}"
fi

if grep -q "resource_group_name = \"merzlikin-tf-state-rg\"" "$TFVARS"; then
  echo "  ✅ Resource group name is correct"
else
  echo -e "  ${RED}❌ Resource group name not set correctly${NC}"
fi

if grep -q "merzlikinairflowpocacr.azurecr.io" "$TFVARS"; then
  echo "  ✅ ACR image references are correct"
else
  echo -e "  ${RED}❌ ACR image references not correct${NC}"
fi
echo ""

# Check 7: Verify module structure
echo "✓ Checking Terraform module structure..."
REQUIRED_MODULES=(
  "terraform/modules/acr"
  "terraform/modules/storage"
  "terraform/modules/postgresql"
  "terraform/modules/redis"
  "terraform/modules/key_vault"
  "terraform/modules/log_analytics"
  "terraform/modules/managed_identity"
  "terraform/modules/aca_environment"
  "terraform/modules/container_apps"
)

for module in "${REQUIRED_MODULES[@]}"; do
  if [ -d "$PROJECT_ROOT/$module" ] && [ -f "$PROJECT_ROOT/$module/main.tf" ]; then
    echo "  ✅ $module"
  else
    echo -e "  ${RED}❌ $module not found or missing main.tf${NC}"
    exit 1
  fi
done
echo ""

echo "=========================================="
echo -e "${GREEN}✅ All validation checks passed!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Build and push Docker images (see docker/README.md)"
echo "2. Run Terraform init and plan"
echo "3. Apply infrastructure"
echo "4. Assign RBAC roles (see RBAC_COMMANDS.md)"
echo ""
