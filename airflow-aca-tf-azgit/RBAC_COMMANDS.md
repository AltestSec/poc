# RBAC Commands - Copy & Paste

Минимальные роли для работы Airflow на Azure Container Apps.

## Шаг 1: Установите переменные

```bash
RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"
PREFIX="merzlikin"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

## Шаг 2: Получите Principal IDs

```bash
SCHEDULER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-scheduler-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WORKER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-worker-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WEBSERVER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-webserver-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
TRIGGERER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-triggerer-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)

echo "Scheduler: $SCHEDULER_PRINCIPAL_ID"
echo "Worker: $WORKER_PRINCIPAL_ID"
echo "Webserver: $WEBSERVER_PRINCIPAL_ID"
echo "Triggerer: $TRIGGERER_PRINCIPAL_ID"
```

## Шаг 3: Получите Resource IDs

```bash
ACR_NAME=$(echo "${PREFIX}${ENV_NAME}acr" | tr -d '-')
STORAGE_NAME=$(echo "${PREFIX}${ENV_NAME}stor" | tr -d '-')

ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
STORAGE_ID=$(az storage account show --name $STORAGE_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

echo "ACR: $ACR_ID"
echo "Storage: $STORAGE_ID"
echo "RG Scope: $RG_SCOPE"
```

## Шаг 4: Назначьте роли (сразу после terraform apply)

### 4.1. AcrPull для всех компонентов (КРИТИЧНО!)

```bash
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $WEBSERVER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $TRIGGERER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
```

### 4.2. Storage Blob Data Contributor для Scheduler и Worker (КРИТИЧНО!)

```bash
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ID
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ID
```

### 4.3. Reader на Resource Group для всех (Рекомендуется)

```bash
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "Reader" --scope $RG_SCOPE
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Reader" --scope $RG_SCOPE
az role assignment create --assignee $WEBSERVER_PRINCIPAL_ID --role "Reader" --scope $RG_SCOPE
az role assignment create --assignee $TRIGGERER_PRINCIPAL_ID --role "Reader" --scope $RG_SCOPE
```

### 4.4. Container Apps Contributor для Worker (Опционально - только если используете ETL Job)

**ВАЖНО:** Эту команду выполняйте только ПОСЛЕ того, как Terraform создаст ETL Job!

```bash
# Сначала получите ID Job (он должен существовать)
ETL_JOB_ID=$(az containerapp job show --name ${ENV_NAME}-etl-runner --resource-group $RESOURCE_GROUP --query id -o tsv 2>/dev/null)

# Проверьте, что Job существует
if [ -z "$ETL_JOB_ID" ]; then
  echo "⚠️  ETL Job не найден. Пропускаем эту роль."
  echo "   Выполните эту команду позже, когда Job будет создан."
else
  echo "✅ ETL Job найден: $ETL_JOB_ID"
  az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Container Apps Contributor" --scope $ETL_JOB_ID
fi
```

**Альтернатива:** Назначьте роль на уровне Resource Group:
```bash
# Worker может запускать любые Container App Jobs в RG
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Container Apps Contributor" --scope $RG_SCOPE
```

## Проверка

```bash
# Проверить роли для Scheduler
az role assignment list --assignee $SCHEDULER_PRINCIPAL_ID --query "[].{Role:roleDefinitionName, Scope:scope}" -o table

# Проверить роли для Worker
az role assignment list --assignee $WORKER_PRINCIPAL_ID --query "[].{Role:roleDefinitionName, Scope:scope}" -o table

# Проверить все роли на ACR
az role assignment list --scope $ACR_ID --query "[].{Role:roleDefinitionName}" -o table

# Проверить все роли на Storage
az role assignment list --scope $STORAGE_ID --query "[].{Role:roleDefinitionName}" -o table
```

---

## Альтернатива: Все команды одной строкой

Если хотите выполнить все сразу (после установки переменных из шагов 1-3):

```bash
# AcrPull для всех
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do az role assignment create --assignee $PRINCIPAL --role "AcrPull" --scope $ACR_ID; done

# Storage Blob для Scheduler и Worker
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID; do az role assignment create --assignee $PRINCIPAL --role "Storage Blob Data Contributor" --scope $STORAGE_ID; done

# Reader для всех
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do az role assignment create --assignee $PRINCIPAL --role "Reader" --scope $RG_SCOPE; done

# Container Apps Contributor для Worker (на уровне RG, чтобы работало для любых Jobs)
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Container Apps Contributor" --scope $RG_SCOPE
```

---

## Для Production окружения

Замените переменные:

```bash
RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-prod"
PREFIX="merzlikin"
```

Затем выполните все команды выше.

---

## Минимум минимума (только критичные роли)

Если нужен абсолютный минимум для запуска (без ETL Job):

```bash
# 1. Установите переменные (шаги 1-3 выше)

# 2. Только критичные роли для запуска Airflow
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $WEBSERVER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $TRIGGERER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ID
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ID
```

Этого достаточно для запуска Airflow (Container Apps запустятся и логи будут сохраняться).

Для использования ETL Job добавьте:
```bash
# После того как Terraform создаст Job
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Container Apps Contributor" --scope $RG_SCOPE
```
