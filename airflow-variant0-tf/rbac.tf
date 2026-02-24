resource "azurerm_role_definition" "aca_job_starter" {
  name        = "${var.prefix}-aca-job-starter"
  scope       = azurerm_resource_group.rg.id
  description = "Allow starting Container Apps Jobs only"

  permissions {
    actions = [
      "microsoft.app/jobs/read",
      "microsoft.app/jobs/start/action"
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.rg.id]
}

resource "azurerm_role_assignment" "airflow_job_starter" {
  scope              = azurerm_resource_group.rg.id
  role_definition_id = azurerm_role_definition.aca_job_starter.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.airflow.principal_id
}