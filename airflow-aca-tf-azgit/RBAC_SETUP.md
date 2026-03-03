# RBAC Setup - Manual Role Assignments

**ВАЖНО:** Role assignments удалены из Terraform, так как Service Principal не имеет прав на создание role assignments (`Microsoft.Authorization/roleAssignments/write`).

Все роли должны быть назначены вручную после развертывания инфраструктуры.

## Быстрый старт (рекомендуется)

Самый простой способ - назначить роль **Contributor** на всю Resource Group для всех managed identities:

```bash
RESOURCE_GROUP="merzlikin-tf-state-rg"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

# Получить Principal IDs после terraform apply
SCHEDULER_PRINCIPAL_ID=$(az identity show --name airflow-poc-scheduler-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WORKER_PRINCIPAL_ID=$(az identity show --name airflow-poc-worker-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WEBSERVER_PRINCIPAL_ID=$(az identity show --name airflow-poc-webserver-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
TRIGGERER_PRINCIPAL_ID=$(az identity show --name airflow-poc-triggerer-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)

# Назначить Contributor на RG для всех компонентов
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do
  echo "Assigning Contributor role to $PRINCIPAL..."
  az role assignment create \
    --assignee $PRINCIPAL \
    --role "Contributor" \
    --scope $RG_SCOPE
done

echo "✅ All roles assigned successfully!"
```

Это даст всем компонентам полные права в пределах Resource Group, включая:
- ✅ Pull образов из ACR
- ✅ Запись логов в Storage
- ✅ Запуск Container App Jobs
- ✅ Чтение секретов из Key Vault (если настроено RBAC)

## Детальная настройка (опционально)

Если нужны более ограниченные права, назначайте роли по отдельности:

## Получение необходимых ID

```bash
# Установите переменные
RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"  # или airflow-prod

# Получите Principal IDs managed identities
SCHEDULER_PRINCIPAL_ID=$(az identity show \
  --name ${ENV_NAME}-scheduler-mi \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv)

WORKER_PRINCIPAL_ID=$(az identity show \
  --name ${ENV_NAME}-worker-mi \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv)

WEBSERVER_PRINCIPAL_ID=$(az identity show \
  --name ${ENV_NAME}-webserver-mi \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv)

TRIGGERER_PRINCIPAL_ID=$(az identity show \
  --name ${ENV_NAME}-triggerer-mi \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv)

# Получите ID ресурсов
ACR_ID=$(az acr show \
  --name merzlikinairflowpocacr \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

STORAGE_ID=$(az storage account show \
  --name merzlikinairflowpocstor \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

KEYVAULT_ID=$(az keyvault show \
  --name merzlikin-airflow-poc-kv \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

echo "Scheduler Principal ID: $SCHEDULER_PRINCIPAL_ID"
echo "Worker Principal ID: $WORKER_PRINCIPAL_ID"
echo "Webserver Principal ID: $WEBSERVER_PRINCIPAL_ID"
echo "Triggerer Principal ID: $TRIGGERER_PRINCIPAL_ID"
echo "ACR ID: $ACR_ID"
echo "Storage ID: $STORAGE_ID"
echo "Key Vault ID: $KEYVAULT_ID"
```

## 1. ACR Pull Rights (Критично!)

Без этих прав Container Apps не смогут pull образы из ACR.

```bash
# Scheduler
az role assignment create \
  --assignee $SCHEDULER_PRINCIPAL_ID \
  --role "AcrPull" \
  --scope $ACR_ID

# Worker
az role assignment create \
  --assignee $WORKER_PRINCIPAL_ID \
  --role "AcrPull" \
  --scope $ACR_ID

# Webserver
az role assignment create \
  --assignee $WEBSERVER_PRINCIPAL_ID \
  --role "AcrPull" \
  --scope $ACR_ID

# Triggerer
az role assignment create \
  --assignee $TRIGGERER_PRINCIPAL_ID \
  --role "AcrPull" \
  --scope $ACR_ID
```

## 2. Storage Blob Data Contributor (Уже есть в Terraform)

Эти роли уже назначены через Terraform для scheduler и worker. Проверка:

```bash
# Проверить существующие роли на Storage Account
az role assignment list \
  --scope $STORAGE_ID \
  --query "[?roleDefinitionName=='Storage Blob Data Contributor'].{Principal:principalId, Role:roleDefinitionName}" \
  -o table
```

Если нужно добавить для webserver и triggerer:

```bash
# Webserver (опционально)
az role assignment create \
  --assignee $WEBSERVER_PRINCIPAL_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID

# Triggerer (опционально)
az role assignment create \
  --assignee $TRIGGERER_PRINCIPAL_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID
```

## 3. Key Vault Secrets User (Опционально)

Если планируете хранить секреты в Key Vault:

```bash
# Scheduler
az role assignment create \
  --assignee $SCHEDULER_PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $KEYVAULT_ID

# Worker
az role assignment create \
  --assignee $WORKER_PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $KEYVAULT_ID

# Webserver
az role assignment create \
  --assignee $WEBSERVER_PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $KEYVAULT_ID
```

## 4. Container Apps Jobs Executor (Для Worker → ETL Job)

Worker должен иметь возможность запускать ETL Job:

```bash
# Получите ID ETL Job
ETL_JOB_ID=$(az containerapp job show \
  --name ${ENV_NAME}-etl-runner \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

# Создайте custom role definition (если еще не создана)
cat > aca-job-starter-role.json <<EOF
{
  "Name": "Container Apps Job Starter",
  "Description": "Can start Container Apps Jobs",
  "Actions": [
    "Microsoft.App/jobs/read",
    "Microsoft.App/jobs/start/action"
  ],
  "NotActions": [],
  "AssignableScopes": [
    "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP"
  ]
}
EOF

# Создайте custom role
az role definition create --role-definition aca-job-starter-role.json

# Назначьте роль Worker identity
az role assignment create \
  --assignee $WORKER_PRINCIPAL_ID \
  --role "Container Apps Job Starter" \
  --scope $ETL_JOB_ID
```

## Альтернатива: Назначить роли на уровне Resource Group

Если хотите упростить управление, можно назначить роли на всю resource group:

```bash
RG_ID=$(az group show --name $RESOURCE_GROUP --query id -o tsv)

# Contributor на всю RG (широкие права, не рекомендуется для production)
az role assignment create \
  --assignee $WORKER_PRINCIPAL_ID \
  --role "Contributor" \
  --scope $RG_ID

# Или более ограниченные роли:
# Reader на RG
az role assignment create \
  --assignee $SCHEDULER_PRINCIPAL_ID \
  --role "Reader" \
  --scope $RG_ID

az role assignment create \
  --assignee $WORKER_PRINCIPAL_ID \
  --role "Reader" \
  --scope $RG_ID

az role assignment create \
  --assignee $WEBSERVER_PRINCIPAL_ID \
  --role "Reader" \
  --scope $RG_ID

az role assignment create \
  --assignee $TRIGGERER_PRINCIPAL_ID \
  --role "Reader" \
  --scope $RG_ID
```

## Проверка назначенных ролей

```bash
# Проверить все роли для Scheduler
az role assignment list \
  --assignee $SCHEDULER_PRINCIPAL_ID \
  --query "[].{Role:roleDefinitionName, Scope:scope}" \
  -o table

# Проверить все роли для Worker
az role assignment list \
  --assignee $WORKER_PRINCIPAL_ID \
  --query "[].{Role:roleDefinitionName, Scope:scope}" \
  -o table

# Проверить все роли на ACR
az role assignment list \
  --scope $ACR_ID \
  --query "[].{Principal:principalId, Role:roleDefinitionName}" \
  -o table

# Проверить все роли на Storage
az role assignment list \
  --scope $STORAGE_ID \
  --query "[].{Principal:principalId, Role:roleDefinitionName}" \
  -o table
```

## Минимально необходимые роли для работы

| Identity | Resource | Role | Критичность |
|----------|----------|------|-------------|
| Scheduler | ACR | AcrPull | ✅ Критично |
| Worker | ACR | AcrPull | ✅ Критично |
| Webserver | ACR | AcrPull | ✅ Критично |
| Triggerer | ACR | AcrPull | ✅ Критично |
| Scheduler | Storage | Storage Blob Data Contributor | ✅ Критично (логи) |
| Worker | Storage | Storage Blob Data Contributor | ✅ Критично (логи) |
| Worker | ETL Job | Container Apps Job Starter | ✅ Критично (запуск job) |
| All | Key Vault | Key Vault Secrets User | ⚠️ Опционально |

## Troubleshooting

### Container App не может pull образ из ACR

**Ошибка:** `Failed to pull image: unauthorized`

**Решение:**
```bash
# Проверьте, что роль AcrPull назначена
az role assignment list \
  --assignee $SCHEDULER_PRINCIPAL_ID \
  --scope $ACR_ID

# Если нет, назначьте
az role assignment create \
  --assignee $SCHEDULER_PRINCIPAL_ID \
  --role "AcrPull" \
  --scope $ACR_ID
```

### Worker не может записать логи в Storage

**Ошибка:** `Access denied to blob storage`

**Решение:**
```bash
# Проверьте роль Storage Blob Data Contributor
az role assignment list \
  --assignee $WORKER_PRINCIPAL_ID \
  --scope $STORAGE_ID

# Если нет, назначьте
az role assignment create \
  --assignee $WORKER_PRINCIPAL_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID
```

### Worker не может запустить ETL Job

**Ошибка:** `Authorization failed for job start`

**Решение:**
```bash
# Создайте custom role и назначьте (см. раздел 4 выше)
```

## Автоматизация через скрипт

Сохраните все команды в скрипт:

```bash
#!/bin/bash
# assign-roles.sh

set -e

RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"

echo "Getting Principal IDs..."
SCHEDULER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-scheduler-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WORKER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-worker-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WEBSERVER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-webserver-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
TRIGGERER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-triggerer-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)

echo "Getting Resource IDs..."
ACR_ID=$(az acr show --name merzlikinairflowpocacr --resource-group $RESOURCE_GROUP --query id -o tsv)

echo "Assigning ACR Pull roles..."
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do
  az role assignment create --assignee $PRINCIPAL --role "AcrPull" --scope $ACR_ID || true
done

echo "Done! All roles assigned."
```

Запуск:
```bash
chmod +x assign-roles.sh
./assign-roles.sh
```
