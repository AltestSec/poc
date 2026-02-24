import os
import requests
from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator

# NOTE: In Container Apps you can override the job execution template by sending a template in POST body. :contentReference[oaicite:3]{index=3}

ARM_RESOURCE = "https://management.azure.com/"
IMDS_URL = "http://169.254.169.254/metadata/identity/oauth2/token"
IMDS_API_VERSION = "2018-02-01"

# MS docs example uses api-version=2023-05-01 in start examples
# Newer API versions exist; for PoC we follow docs pattern.
ACA_JOBS_API_VERSION = "2023-05-01"

def get_arm_token() -> str:
    r = requests.get(
        IMDS_URL,
        params={"api-version": IMDS_API_VERSION, "resource": ARM_RESOURCE},
        headers={"Metadata": "true"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["access_token"]

def start_job(job_name: str, env_overrides: dict | None = None, command_override: list[str] | None = None):
    sub = os.environ["AZ_SUBSCRIPTION_ID"]
    rg  = os.environ["AZ_RESOURCE_GROUP"]

    token = get_arm_token()
    url = (
        f"https://management.azure.com/subscriptions/{sub}"
        f"/resourceGroups/{rg}"
        f"/providers/Microsoft.App/jobs/{job_name}/start"
        f"?api-version={ACA_JOBS_API_VERSION}"
    )

    # Build execution template override.
    # Important: when overriding, the job's entire template is replaced for that execution. :contentReference[oaicite:4]{index=4}
    containers = [{
        "name": "main",
        "image": os.environ.get("ETL_IMAGE_OVERRIDE", ""),  # optional; can be blank => omit below
        "resources": {"cpu": 0.5, "memory": "1Gi"},
    }]

    # Remove empty image override so base job image is used if you prefer
    if not containers[0]["image"]:
        containers[0].pop("image", None)

    if env_overrides:
        containers[0]["env"] = [{"name": k, "value": str(v)} for k, v in env_overrides.items()]

    if command_override:
        containers[0]["command"] = command_override

    payload = {"containers": containers}

    r = requests.post(
        url,
        json=payload,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        timeout=30,
    )
    r.raise_for_status()
    return r.json() if r.content else {"status": "started"}

def run_etl_variant_a():
    # One job, different input params:
    job_name = os.environ["ACA_JOB_NAME"]
    return start_job(
        job_name=job_name,
        env_overrides={"RUN_ID": "variant-a", "REGION": "east", "MODE": "daily"},
        command_override=["/bin/sh", "-lc", "echo ETL variant A; env | sort; sleep 5"],
    )

def run_etl_variant_b():
    job_name = os.environ["ACA_JOB_NAME"]
    return start_job(
        job_name=job_name,
        env_overrides={"RUN_ID": "variant-b", "REGION": "east", "MODE": "backfill"},
        command_override=["/bin/sh", "-lc", "echo ETL variant B; env | sort; sleep 5"],
    )

def run_jobname_per_dag():
    # If you create multiple jobs in Terraform, you can pick which to start per DAG.
    # Example: ACA_JOB_NAME_2="poc-airflow-etl-2"
    job_name = os.environ.get("ACA_JOB_NAME_2", os.environ["ACA_JOB_NAME"])
    return start_job(job_name=job_name, env_overrides={"RUN_ID": "jobname-per-dag"})

with DAG(
    dag_id="aca_job_start_examples",
    start_date=datetime(2026, 1, 1),
    schedule="0 * * * *",
    catchup=False,
    max_active_runs=10,
) as dag:
    PythonOperator(task_id="etl_variant_a", python_callable=run_etl_variant_a)
    PythonOperator(task_id="etl_variant_b", python_callable=run_etl_variant_b)
    PythonOperator(task_id="etl_jobname_per_dag", python_callable=run_jobname_per_dag)