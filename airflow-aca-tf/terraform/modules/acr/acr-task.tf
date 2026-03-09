# ACR Task for building Airflow images
# This task is stored in ACR and can be triggered without accessing the registry

resource "azurerm_container_registry_task" "build_images" {
  name                  = "build-airflow-images"
  container_registry_id = azurerm_container_registry.acr.id
  platform {
    os           = "Linux"
    architecture = "amd64"
  }

  # Use the ACR Tasks YAML from the repo
  encoded_step {
    task_content = <<-EOT
      version: v1.1.0
      steps:
        # Build both images concurrently
        - id: build-airflow
          build: >
            -t {{.Run.Registry}}/airflow:{{.Run.ID}}
            -t {{.Run.Registry}}/airflow:$TAG
            -t {{.Run.Registry}}/airflow:latest
            -f airflow/Dockerfile
            --platform linux/amd64
            airflow
          when: ["-"]

        - id: build-etl-runner
          build: >
            -t {{.Run.Registry}}/etl-runner:{{.Run.ID}}
            -t {{.Run.Registry}}/etl-runner:$TAG
            -t {{.Run.Registry}}/etl-runner:latest
            -f etl-runner/Dockerfile
            --platform linux/amd64
            etl-runner
          when: ["-"]

        # Push all images after successful builds
        - push:
            - "{{.Run.Registry}}/airflow:{{.Run.ID}}"
            - "{{.Run.Registry}}/airflow:$TAG"
            - "{{.Run.Registry}}/airflow:latest"
          when: ["build-airflow"]

        - push:
            - "{{.Run.Registry}}/etl-runner:{{.Run.ID}}"
            - "{{.Run.Registry}}/etl-runner:$TAG"
            - "{{.Run.Registry}}/etl-runner:latest"
          when: ["build-etl-runner"]
    EOT
  }

  # Source code location
  source_trigger {
    name           = "source-trigger"
    events         = ["commit"]
    repository_url = var.repository_url
    source_type    = "Github" # or "AzureDevOps"
    branch         = "main"
    
    authentication {
      token_type = "PAT"
      token      = var.git_pat_token
    }
  }

  # Enable manual trigger
  agent_setting {
    cpu = 2
  }

  tags = var.tags
}

# Output the task name for triggering from pipeline
output "acr_task_name" {
  value       = azurerm_container_registry_task.build_images.name
  description = "Name of the ACR Task for building images"
}
