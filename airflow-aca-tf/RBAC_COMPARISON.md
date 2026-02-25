# RBAC Roles Comparison

## Что было убрано из Terraform

```hcl
# modules/container_apps/main.tf (строки 32-43)

resource "azurerm_role_assignment" "scheduler_blob" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.scheduler_principal_id
}

resource "azurerm_role_assignment" "worker_blob" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.worker_principal_id
}
```

**Причина удаления:** Service Principal не имеет прав `Microsoft.Authorization/roleAssignments/write`

---

## Сравнение подходов

### Вариант 1: Contributor на Resource Group (Простой)

**Скрипт:** `assign-roles.sh`

| Identity | Scope | Role | Права |
|----------|-------|------|-------|
| Scheduler | Resource Group | Contributor | Полные права на все ресурсы в RG |
| Worker | Resource Group | Contributor | Полные права на все ресурсы в RG |
| Webserver | Resource Group | Contributor | Полные права на все ресурсы в RG |
| Triggerer | Resource Group | Contributor | Полные права на все ресурсы в RG |

**Плюсы:**
- ✅ Простота - одна команда для всех
- ✅ Не нужно знать ID конкретных ресурсов
- ✅ Автоматически работает для новых ресурсов в RG

**Минусы:**
- ❌ Избыточные права (принцип least privilege нарушен)
- ❌ Компоненты могут изменять/удалять ресурсы

**Использование:**
```bash
./assign-roles.sh merzlikin-tf-state-rg airflow-poc
```

---

### Вариант 2: Минимальные роли (Рекомендуется)

**Скрипт:** `assign-roles-minimal.sh`

| Identity | Scope | Role | Зачем нужно |
|----------|-------|------|-------------|
| **Все компоненты** | ACR | AcrPull | Pull образов из ACR |
| **Все компоненты** | Resource Group | Reader | Service discovery, чтение метаданных |
| **Scheduler** | Storage Account | Storage Blob Data Contributor | Запись логов в Blob |
| **Worker** | Storage Account | Storage Blob Data Contributor | Запись логов в Blob |
| **Worker** | ETL Job | Container Apps Contributor | Запуск ETL Job через ARM API |

**Плюсы:**
- ✅ Минимальные необходимые права (least privilege)
- ✅ Безопаснее для production
- ✅ Компоненты не могут случайно изменить инфраструктуру

**Минусы:**
- ❌ Сложнее настройка
- ❌ Нужно знать ID всех ресурсов
- ❌ При добавлении новых ресурсов нужно обновлять роли

**Использование:**
```bash
./assign-roles-minimal.sh merzlikin-tf-state-rg airflow-poc merzlikin
```

---

### Вариант 3: Гибридный (Баланс)

Комбинация Reader на RG + точечные роли на критичные ресурсы:

```bash
RESOURCE_GROUP="merzlikin-tf-state-rg"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

# 1. Reader на RG для всех (service discovery)
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do
  az role assignment create --assignee $PRINCIPAL --role "Reader" --scope $RG_SCOPE
done

# 2. Contributor только на Storage Account (для логов)
STORAGE_ID=$(az storage account show --name merzlikinairflowpocstor --resource-group $RESOURCE_GROUP --query id -o tsv)
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "Contributor" --scope $STORAGE_ID
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Contributor" --scope $STORAGE_ID

# 3. AcrPull на ACR для всех
ACR_ID=$(az acr show --name merzlikinairflowpocacr --resource-group $RESOURCE_GROUP --query id -o tsv)
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do
  az role assignment create --assignee $PRINCIPAL --role "AcrPull" --scope $ACR_ID
done
```

---

## Детальное описание ролей

### AcrPull
- **Scope:** Azure Container Registry
- **Права:** Только pull образов
- **Нужно для:** Всех Container Apps (scheduler, worker, webserver, triggerer)
- **Критичность:** ✅ Обязательно (без этого контейнеры не запустятся)

### Storage Blob Data Contributor
- **Scope:** Storage Account
- **Права:** Чтение, запись, удаление blob'ов
- **Нужно для:** Scheduler и Worker (для записи логов)
- **Критичность:** ✅ Обязательно (иначе логи не сохранятся)

### Reader
- **Scope:** Resource Group
- **Права:** Только чтение метаданных ресурсов
- **Нужно для:** Всех компонентов (service discovery)
- **Критичность:** ⚠️ Желательно (для корректной работы)

### Container Apps Contributor
- **Scope:** Container App Job (ETL runner)
- **Права:** Управление Container App Jobs
- **Нужно для:** Worker (для запуска ETL Job)
- **Критичность:** ✅ Обязательно (если используется ETL Job)

### Contributor (на RG)
- **Scope:** Resource Group
- **Права:** Полные права на все ресурсы (кроме управления доступом)
- **Нужно для:** Упрощения управления
- **Критичность:** ⚠️ Избыточно, но удобно

---

## Рекомендации

### Для Development/PoC:
Используйте **Вариант 1** (Contributor на RG):
```bash
./assign-roles.sh merzlikin-tf-state-rg airflow-poc
```

### Для Production:
Используйте **Вариант 2** (Минимальные роли):
```bash
./assign-roles-minimal.sh merzlikin-tf-state-rg airflow-prod merzlikin
```

### Для быстрого старта с планами улучшить:
Используйте **Вариант 3** (Гибридный) - скопируйте команды выше

---

## Проверка назначенных ролей

```bash
# Проверить роли для конкретного identity
PRINCIPAL_ID="<principal-id>"
az role assignment list --assignee $PRINCIPAL_ID --query "[].{Role:roleDefinitionName, Scope:scope}" -o table

# Проверить все роли на ACR
ACR_ID=$(az acr show --name merzlikinairflowpocacr --resource-group merzlikin-tf-state-rg --query id -o tsv)
az role assignment list --scope $ACR_ID --query "[].{Identity:principalId, Role:roleDefinitionName}" -o table

# Проверить все роли на Storage
STORAGE_ID=$(az storage account show --name merzlikinairflowpocstor --resource-group merzlikin-tf-state-rg --query id -o tsv)
az role assignment list --scope $STORAGE_ID --query "[].{Identity:principalId, Role:roleDefinitionName}" -o table
```

---

## Troubleshooting

### Container App не запускается - "Failed to pull image"
**Причина:** Нет роли AcrPull  
**Решение:**
```bash
ACR_ID=$(az acr show --name merzlikinairflowpocacr --resource-group merzlikin-tf-state-rg --query id -o tsv)
az role assignment create --assignee <principal-id> --role "AcrPull" --scope $ACR_ID
```

### Логи не сохраняются в Storage
**Причина:** Нет роли Storage Blob Data Contributor  
**Решение:**
```bash
STORAGE_ID=$(az storage account show --name merzlikinairflowpocstor --resource-group merzlikin-tf-state-rg --query id -o tsv)
az role assignment create --assignee <principal-id> --role "Storage Blob Data Contributor" --scope $STORAGE_ID
```

### Worker не может запустить ETL Job
**Причина:** Нет прав на запуск Job  
**Решение:**
```bash
ETL_JOB_ID=$(az containerapp job show --name airflow-poc-etl-runner --resource-group merzlikin-tf-state-rg --query id -o tsv)
az role assignment create --assignee <worker-principal-id> --role "Container Apps Contributor" --scope $ETL_JOB_ID
```
