# ACR Tasks Guide - Building Images with YAML

This guide explains how to use Azure Container Registry (ACR) Tasks with YAML definitions instead of Docker@2 tasks.

## Why ACR Tasks YAML?

**Benefits over Docker@2:**
- ✅ No Docker daemon required on build agent
- ✅ Declarative YAML format for complex workflows
- ✅ Parallel builds with dependency management
- ✅ Built-in testing and conditional push
- ✅ Better for private ACR (automatic authentication)
- ✅ Build logs stored in ACR

## ACR Tasks YAML Format

ACR Tasks uses a declarative YAML format (v1.1.0) that supports parallel builds, conditional execution, and testing.

### Basic Structure

```yaml
version: v1.1.0
steps:
  - id: step-name
    build: -t $Registry/image:$ID .
    when: ["-"]  # "-" means run immediately
  
  - push: ["$Registry/image:$ID"]
    when: ["step-name"]  # Run after step-name succeeds
```

### Built-in Variables

- `{{.Run.Registry}}` - ACR login server (e.g., myacr.azurecr.io)
- `{{.Run.ID}}` - Unique run ID (e.g., ca1)
- `$TAG` - Custom variables passed via `--set TAG=value`

## Implementation

### Before (Docker@2)

```yaml
- task: Docker@2
  displayName: 'Build Airflow Image'
  inputs:
    command: build
    buildContext: '$(dockerRoot)/airflow'
    dockerfile: '$(dockerRoot)/airflow/Dockerfile'
    repository: '$(ACR_LOGIN_SERVER)/airflow'
    tags: |
      $(RESOLVED_TAG)
      $(Build.BuildId)

- task: Docker@2
  displayName: 'Push Airflow Image'
  inputs:
    command: push
    repository: '$(ACR_LOGIN_SERVER)/airflow'
    tags: |
      $(RESOLVED_TAG)
      $(Build.BuildId)
```

### After (ACR Tasks with YAML)

**1. Create ACR Task YAML** (`acr-tasks/build-all.yaml`):

```yaml
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
```

**2. Update Azure Pipeline**:

```yaml
- task: AzureCLI@2
  displayName: 'Build and Push Images (ACR Tasks)'
  inputs:
    azureSubscription: ${{ parameters.serviceConnection }}
    scriptType: bash
    scriptLocation: inlineScript
    workingDirectory: ${{ parameters.dockerRoot }}
    inlineScript: |
      az acr run \
        --registry $(ACR_NAME_RESOLVED) \
        --file ../acr-tasks/build-all.yaml \
        --set TAG=$(RESOLVED_TAG) \
        --platform linux/amd64 \
        .
```

## Advanced Pattern: Build with Tests

Based on the Microsoft example, here's how to build, test, then conditionally push:

```yaml
version: v1.1.0
steps:
  # Build app and test images concurrently
  - id: build-hello-world
    build: -t {{.Run.Registry}}/hello-world:{{.Run.ID}} -f hello-world.dockerfile .
    when: ["-"]
  
  - id: build-hello-world-test
    build: -t hello-world-test -f hello-world.dockerfile .
    when: ["-"]
  
  # Run application container
  - id: hello-world
    cmd: {{.Run.Registry}}/hello-world:{{.Run.ID}}
    when: ["build-hello-world"]
  
  # Run tests against application
  - id: func-tests
    cmd: hello-world-test
    env:
      - TEST_TARGET_URL=hello-world
    when: ["hello-world"]
  
  # Only push if tests pass
  - push: ["{{.Run.Registry}}/hello-world:{{.Run.ID}}"]
    when: ["func-tests"]
```

## Available ACR Task Files

### 1. `build-all.yaml` - Build Both Images

Builds Airflow and ETL Runner in parallel.

**Usage:**
```bash
az acr run \
  --registry myacr \
  --file acr-tasks/build-all.yaml \
  --set TAG=v1.0.0 \
  docker
```

### 2. `build-airflow.yaml` - Airflow Only

```bash
az acr run \
  --registry myacr \
  --file acr-tasks/build-airflow.yaml \
  --set TAG=v2.9.3 \
  docker
```

### 3. `build-etl-runner.yaml` - ETL Runner Only

```bash
az acr run \
  --registry myacr \
  --file acr-tasks/build-etl-runner.yaml \
  --set TAG=v1.0.0 \
  docker
```

## ACR Tasks YAML Reference

### Step Types

**build** - Build Docker image:
```yaml
- id: my-build
  build: -t {{.Run.Registry}}/image:tag -f Dockerfile .
  when: ["-"]
```

**push** - Push images:
```yaml
- push: ["{{.Run.Registry}}/image:tag"]
  when: ["my-build"]
```

**cmd** - Run container:
```yaml
- id: run-tests
  cmd: test-image
  env:
    - VAR=value
  when: ["build-tests"]
```

### Execution Control

**when** - Dependencies:
- `["-"]` - Run immediately (parallel)
- `["step-id"]` - Run after step-id
- `["step1", "step2"]` - Run after both

## Local Testing

```bash
# Test the YAML file
az acr run \
  --registry myacr \
  --file acr-tasks/build-all.yaml \
  --set TAG=test-v1 \
  --platform linux/amd64 \
  docker
```

## Resources

- [ACR Tasks YAML Reference](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-tasks-reference-yaml)
- [Multi-step Tasks](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-tasks-multi-step)
