"""
dags/etl_with_aca_job.py
========================
Example DAG: triggers etl-runner ACA Job, waits for completion.

Demonstrates:
  - ACAJobRunOperator  (custom plugin) — triggers etl-runner via ARM API
  - Managed Identity flow (no stored credentials)
  - Deferrable sensor (requires Triggerer component)
  - XCom for passing execution name downstream
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.python import PythonOperator

# Custom operator — lives in plugins/aca_job_operator.py
from aca_job_operator import ACAJobRunOperator

# ── DAG defaults ──────────────────────────────────────────────
default_args = {
    "owner": "data-team",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "email_on_failure": False,
}

# ── Variables — set in Airflow UI (Admin → Variables) ─────────
SUBSCRIPTION_ID = Variable.get("AZURE_SUBSCRIPTION_ID")
RESOURCE_GROUP  = Variable.get("AZURE_RESOURCE_GROUP")
ETL_JOB_NAME    = Variable.get("ACA_ETL_JOB_NAME", default_var="airflow-poc-etl-runner")

# ── DAG ───────────────────────────────────────────────────────
with DAG(
    dag_id="etl_with_aca_job",
    description="Runs ETL pipeline via ACA Job (etl-runner)",
    schedule="0 2 * * *",       # Daily at 02:00 UTC
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args=default_args,
    tags=["etl", "aca", "dbt"],
    doc_md="""
## ETL with ACA Job

Triggers the `etl-runner` Azure Container Apps Job which runs DBT transforms.

### Auth flow
Worker uses **Managed Identity** → no credentials stored in Airflow.
Requires: Worker MI has `Container Apps Jobs Executor` role on the job.
See `infra/scripts/assign-roles.sh`.

### Scaling
Workers scale from 0→N based on Redis queue depth (KEDA).
etl-runner Job has no timeout limit — runs as long as needed.
""",
) as dag:

    # Step 1: Pre-flight check (lightweight, runs on worker)
    def check_source_data(**context):
        """Verify source data is available before launching expensive ETL job."""
        import logging
        log = logging.getLogger(__name__)
        # Add your pre-flight logic here (e.g., check blob exists, row count, etc.)
        log.info("Pre-flight check passed for run_id=%s", context["run_id"])
        return "ok"

    preflight = PythonOperator(
        task_id="preflight_check",
        python_callable=check_source_data,
    )

    # Step 2: Trigger etl-runner ACA Job
    # Worker calls ARM API using Managed Identity — no credentials needed.
    # Operator polls for completion (default: every 15s, timeout: 4h).
    run_etl = ACAJobRunOperator(
        task_id="run_etl_runner",
        subscription_id=SUBSCRIPTION_ID,
        resource_group=RESOURCE_GROUP,
        job_name=ETL_JOB_NAME,
        environment_variables={
            "DBT_TARGET": "prod",
            "DBT_MODELS": "+my_mart",          # dbt model selector
            "AIRFLOW_DAG_RUN_ID": "{{ run_id }}",
        },
        poll_interval=15,
        timeout=14400,   # 4h — adjust as needed; ACA Jobs have no system limit
    )

    # Step 3: Post-ETL validation (runs on Airflow worker)
    def validate_output(**context):
        """Verify output tables were populated."""
        import logging
        log = logging.getLogger(__name__)
        execution_name = context["ti"].xcom_pull(task_ids="run_etl_runner")
        log.info("ETL completed. Job execution: %s", execution_name)
        # Add your validation logic here (e.g., row count check, schema validation)
        log.info("Output validation passed")

    validate = PythonOperator(
        task_id="validate_output",
        python_callable=validate_output,
    )

    # ── Dependencies ──────────────────────────────────────────
    preflight >> run_etl >> validate
