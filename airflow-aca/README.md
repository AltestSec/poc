# Airflow on Azure Container Apps

Self-hosted Apache Airflow with **CeleryExecutor** running entirely on Azure Container Apps — no Kubernetes, no VMs.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  ACA Environment  (shared network boundary, Log Analytics)           │
│                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │ airflow-scheduler│  │airflow-webserver│  │ airflow-triggerer   │  │
│  │ min=1 max=1      │  │ min=0(1) max=1  │  │ min=1 max=1         │  │
│  │ 0.5vCPU / 1Gi   │  │ 0.25vCPU/0.5Gi │  │ 0.25vCPU / 0.5Gi   │  │
│  │ ingress: OFF     │  │ ingress: internal│  │ ingress: OFF        │  │
│  └────────┬────────┘  └────────┬────────┘  └─────────────────────┘  │
│           │                    │                    │ async sensors   │
│           │         ┌──────────┴────────┐           │                │
│           │         │  airflow-worker   │◄──────────┘                │
│           │         │ min=0 max=10      │                            │
│           │         │ 0.5vCPU / 1Gi     │                            │
│           │         │ KEDA: Redis queue │                            │
│           │         └──────────┬────────┘                            │
│           │                    │ ARM API (Managed Identity)          │
│           │                    ▼                                     │
│           │         ┌──────────────────┐                             │
│           │         │  etl-runner      │  ACA Job (Manual trigger)  │
│           │         │  1vCPU / 2Gi     │  no timeout limit          │
│           │         │  replicaTimeout=4h│                            │
│           │         └──────────────────┘                             │
│                                                                      │
│  ─ ─ ─ ─ Shared volumes ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
│  Azure Files /opt/airflow/dags  (ReadOnly mount, all components)     │
└──────────────────────────────────────────────────────────────────────┘

Managed dependencies (outside ACA Environment):
  Azure Database for PostgreSQL Flexible Server  ← metadata DB
  Azure Cache for Redis Standard C1              ← Celery broker + result backend
  Azure Storage Account
    ├── File Share: airflow-dags                 ← DAG files (mounted in all containers)
    └── Blob Container: airflow-logs             ← Remote task logs (survive scale-to-zero)
  Azure Key Vault                                ← secrets (Fernet key, DB password, etc.)
```

---

## Components

| Component | Type | Replicas | CPU / RAM | Purpose |
|---|---|---|---|---|
| `airflow-scheduler` | Container App | min=1 max=1 | 0.5 / 1Gi | Parses DAGs, schedules tasks |
| `airflow-webserver` | Container App | min=0 max=1 | 0.25 / 0.5Gi | UI, REST API |
| `airflow-triggerer` | Container App | min=1 max=1 | 0.25 / 0.5Gi | Async/deferrable operators |
| `airflow-worker` | Container App | min=0 max=10 | 0.5 / 1Gi | Executes Celery tasks |
| `etl-runner` | ACA Job | n/a | 1.0 / 2Gi | Run-to-completion ETL (DBT) |

### Production sizing (`deploymentMode=production`)

| Component | CPU / RAM | Min replicas |
|---|---|---|
| Scheduler | 1.0 / 2Gi | 2 (HA mode — see note below) |
| Webserver | 0.5 / 1Gi | 1 |
| Worker | 1.0 / 2Gi | 0 |
| Triggerer | 0.25 / 0.5Gi | 1 |
| PostgreSQL | Standard_D2ds_v4 + Zone HA | — |
| Redis | Premium P1 | — |

---

## Scheduler HA (production)

Airflow 2.x supports running multiple scheduler instances simultaneously. However, **setting `minReplicas=2` alone is not sufficient** — the following is required:

```ini
[scheduler]
num_runs = -1   # Run forever (don't exit after N heartbeats)
```

Set via environment variable:
```
AIRFLOW__SCHEDULER__NUM_RUNS=-1
```

Both schedulers coordinate exclusively through the PostgreSQL metadata database — there is no inter-scheduler communication. Each scheduler independently picks up tasks and updates the DB with row-level locking to avoid conflicts.

**For PoC: `minReplicas=1` is sufficient.** A single scheduler failure causes a brief gap in scheduling (typically resolved within 60s by ACA container restart policy).

---

## etl-runner: ARM API trigger via Managed Identity

The `airflow-worker` triggers `etl-runner` without storing any Azure credentials. The flow:

```
Worker Container App
  └─ Managed Identity (user-assigned)
       └─ Role: "Container Apps Jobs Executor" on etl-runner job
            └─ ARM API call: POST /jobs/etl-runner/start
                 └─ ACA creates a new Job Execution (isolated container)
```

**Why this approach:**
- No Service Principal or client secret stored in Airflow connections
- `DefaultAzureCredential` in the operator resolves to Managed Identity automatically when running on ACA
- Per-execution environment variables let Airflow pass context (run_id, model selectors, target environment)
- ACA Jobs have **no system-imposed timeout** — `replicaTimeout` is configurable (default 4h in this template)

**RBAC setup** (runs once after Bicep deploy):
```bash
cd infra/scripts
./assign-roles.sh <resource-group> <worker-principal-id> <etl-runner-job-id>
```

The Bicep template outputs all required IDs. The `deploy.sh` script runs this automatically.

---

## DAG storage: Azure Files

All Airflow components (scheduler, webserver, workers, triggerer) mount the same Azure Files share as a **ReadOnly volume** at `/opt/airflow/dags`.

```
Azure Storage Account
  └── File Share: airflow-dags
        ├── my_etl_dag.py
        ├── another_dag.py
        └── subdirectory/
              └── complex_dag.py
```

**Upload DAGs:**
```bash
az storage file upload-batch \
  --account-name <storage-account> \
  --destination airflow-dags \
  --source ./dags
```

The scheduler auto-detects new/modified files via `dag_dir_list_interval` (default: 300s). For faster updates, set `AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL=30`.

> **Note:** Azure Container Apps does **not** support mounting Azure Blob Storage as a filesystem. Only Azure Files (SMB/NFS) is supported for volume mounts.

---

## Remote logging

Workers scale to zero when idle. Task logs written to ephemeral container storage would be lost on scale-down. This deployment writes logs to **Azure Blob Storage** instead:

```ini
AIRFLOW__LOGGING__REMOTE_LOGGING=True
AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER=wasb://airflow-logs@<account>.blob.core.windows.net
AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID=azure_blob_logs
```

The Airflow connection `azure_blob_logs` uses the worker's Managed Identity — configure in Airflow UI:
- **Conn Type:** `wasb`
- **Login:** *(leave empty — uses Managed Identity)*
- **Extra:** `{"managed_identity_client_id": "<worker-mi-client-id>"}`

---

## Triggerer: deferrable operators

The `airflow-triggerer` component is required for **deferrable operators** (async sensors). Without it, sensors run synchronously and occupy a worker slot for their entire wait period.

Examples of deferrable operators:
- `TimeDeltaSensorAsync` — wait without blocking a worker
- `HttpSensorAsync` — poll external endpoint
- `ExternalTaskSensorAsync` — wait for another DAG

The triggerer runs as a separate Container App (`min=1`) and handles up to ~1000 concurrent deferrable triggers per instance.

```python
# Instead of:
from airflow.sensors.time_delta import TimeDeltaSensor   # blocks a worker

# Use:
from airflow.sensors.time_delta import TimeDeltaSensorAsync  # uses triggerer
```

---

## Production additions (not in PoC)

### Flower — Celery worker monitoring

Flower provides a web UI to monitor worker status, task queues, and throughput.

Add as an optional Container App:
```bicep
// Not included in main.bicep — add manually for production
resource flowerApp 'Microsoft.App/containerApps@2024-03-01' = {
  // command: ['airflow', 'celery', 'flower']
  // ingress: internal, port 5555
  // min=0 max=1
}
```

Access via `az containerapp tunnel` or Application Gateway.

### Private Endpoints (production)

In production, both PostgreSQL and Redis should be exposed only via **Private Endpoints** — no public IP.

```bicep
// PostgreSQL: set publicNetworkAccess = 'Disabled'
// Redis: set publicNetworkAccess = 'Disabled'
// Add Private Endpoints for both in the ACA VNet subnet
```

This requires deploying the ACA Environment with a custom VNet (`infrastructureSubnetId`). See [ACA Landing Zone Accelerator](https://github.com/Azure/ACA-Landing-Zone-Accelerator) for hub-spoke topology.

### Application Gateway (production)

The webserver uses **internal ingress** — not reachable from the internet.

For external access without a VPN:
1. Deploy Application Gateway v2 in front of the ACA Environment
2. Configure backend pool → webserver FQDN
3. Add WAF policy (OWASP 3.2 ruleset)
4. TLS termination at App Gateway

Alternatively for internal teams: use Azure Bastion or a VPN gateway.

---

## Quick start

### Prerequisites

- Azure CLI 2.57+
- Python 3.11+ (for key generation)
- Bicep CLI (`az bicep install`)

### Deploy PoC

```bash
# 1. Clone / download this repository
cd infra

# 2. Login to Azure
az login
az account set --subscription <your-subscription-id>

# 3. Deploy (generates secrets automatically)
chmod +x scripts/deploy.sh
./scripts/deploy.sh poc westeurope my-airflow-rg

# 4. Upload your DAGs
az storage file upload-batch \
  --account-name <output: storageAccountName> \
  --destination airflow-dags \
  --source ../dags

# 5. Access webserver (port-forward to local)
az containerapp tunnel \
  --name airflow-poc-webserver \
  --resource-group my-airflow-rg \
  --port 8080:8080
# Open http://localhost:8080
```

### Set Airflow Variables

In Airflow UI → Admin → Variables, set:

| Key | Value |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Your subscription ID |
| `AZURE_RESOURCE_GROUP` | Resource group name |
| `ACA_ETL_JOB_NAME` | `airflow-poc-etl-runner` |

---

## File structure

```
airflow-aca/
├── infra/
│   ├── bicep/
│   │   ├── main.bicep              # All Azure resources
│   │   ├── main.poc.bicepparam     # PoC parameters
│   │   └── main.prod.bicepparam    # Production parameters
│   └── scripts/
│       ├── deploy.sh               # Full deploy script
│       └── assign-roles.sh         # RBAC: worker → etl-runner
├── airflow/
│   ├── Dockerfile                  # Custom Airflow image
│   ├── airflow.cfg.reference       # Config documentation
│   ├── plugins/
│   │   └── aca_job_operator.py     # ARM API operator (Managed Identity)
│   └── etl-runner/
│       ├── Dockerfile              # etl-runner ACA Job image
│       └── entrypoint.sh           # DBT runner entrypoint
├── dags/
│   └── etl_with_aca_job.py         # Example DAG
└── README.md
```

---

## Cost estimate (PoC)

| Component | SKU | ~$/month |
|---|---|---|
| Scheduler (always-on 0.5vCPU/1Gi) | ACA Consumption | ~$15–20 |
| Triggerer (always-on 0.25vCPU/0.5Gi) | ACA Consumption | ~$8–12 |
| Webserver (min=0) | ACA Consumption | ~$3–8 |
| Workers (scale-to-zero) | ACA Consumption | pay per task |
| PostgreSQL Flexible Server | Burstable B1ms | ~$15 |
| Redis Standard C1 (1 GB) | — | ~$25 |
| Azure Files Standard LRS 5GB | — | ~$2 |
| Log Analytics (30 day retention) | — | ~$3–5 |
| **Total PoC** | | **~$71–87/month** |

Workers billed per-second only while tasks are running. For a pipeline with 2h of daily execution across 3 workers: ~$8–15/month additional.

---

## Known limitations & caveats

| Topic | Detail |
|---|---|
| DAG sync latency | Scheduler rescans DAG folder every 300s by default. Reduce with `AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL=30` for dev. |
| Webserver cold start | With `minReplicas=0`, webserver takes 30–60s to start. Set `minReplicas=1` if UI availability matters. |
| No git-sync | DAGs are uploaded manually or via CI/CD pipeline. There is no built-in git-sync in ACA (unlike Helm chart for AKS). Add a CI/CD step to `az storage file upload-batch`. |
| Redis `maxmemory-policy` | Must be set to `noeviction` — Celery messages must never be silently dropped. Configured in Bicep. |
| Celery result backend | Uses PostgreSQL (`db+postgresql://`), not Redis. More reliable for task result storage. |
| etl-runner job timeout | `replicaTimeout` defaults to 4h in this template. Increase for very long transforms. ACA Jobs have no system-imposed maximum. |
