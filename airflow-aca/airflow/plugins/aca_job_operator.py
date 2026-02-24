"""
plugins/aca_job_operator.py
===========================
Airflow operator to trigger Azure Container Apps Jobs via ARM API
using Managed Identity (no credentials needed).

Usage in DAG:
    from plugins.aca_job_operator import ACAJobRunOperator

    run_etl = ACAJobRunOperator(
        task_id="run_etl_job",
        subscription_id="{{ var.value.AZURE_SUBSCRIPTION_ID }}",
        resource_group="my-rg",
        job_name="airflow-poc-etl-runner",
        environment_variables={
            "DBT_TARGET": "prod",
            "RUN_ID": "{{ run_id }}",
        },
        task_id="run_etl",
        dag=dag,
    )

Requirements:
    - Worker Managed Identity must have 'Container Apps Jobs Executor' role on the job.
      See infra/scripts/assign-roles.sh
    - pip install azure-mgmt-appcontainers azure-identity
"""

from __future__ import annotations

import time
import logging
from typing import Any

from airflow.models import BaseOperator
from airflow.utils.decorators import apply_defaults

log = logging.getLogger(__name__)


class ACAJobRunOperator(BaseOperator):
    """
    Triggers an Azure Container Apps Job execution via ARM API.
    Uses DefaultAzureCredential → Managed Identity (no stored secrets).

    :param subscription_id:     Azure subscription ID
    :param resource_group:      Resource group containing the ACA Job
    :param job_name:            ACA Job name (e.g. 'airflow-poc-etl-runner')
    :param environment_variables: Additional env vars to pass to the job execution
    :param poll_interval:       Seconds between status polls (default: 15)
    :param timeout:             Max seconds to wait for completion (default: 14400 = 4h)
    """

    template_fields = ("environment_variables", "job_name")
    ui_color = "#e8f4fd"

    @apply_defaults
    def __init__(
        self,
        subscription_id: str,
        resource_group: str,
        job_name: str,
        environment_variables: dict[str, str] | None = None,
        poll_interval: int = 15,
        timeout: int = 14400,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.subscription_id = subscription_id
        self.resource_group = resource_group
        self.job_name = job_name
        self.environment_variables = environment_variables or {}
        self.poll_interval = poll_interval
        self.timeout = timeout

    def execute(self, context: dict) -> str:
        try:
            from azure.identity import DefaultAzureCredential
            from azure.mgmt.appcontainers import ContainerAppsAPIClient
            from azure.mgmt.appcontainers.models import (
                JobExecutionTemplate,
                JobExecutionContainer,
                EnvironmentVar,
            )
        except ImportError as e:
            raise ImportError(
                "azure-mgmt-appcontainers and azure-identity are required. "
                "Install with: pip install azure-mgmt-appcontainers azure-identity"
            ) from e

        # DefaultAzureCredential automatically uses Managed Identity when running on ACA
        credential = DefaultAzureCredential()
        client = ContainerAppsAPIClient(credential, self.subscription_id)

        # Build env vars for this execution
        env_vars = [
            EnvironmentVar(name=k, value=v)
            for k, v in self.environment_variables.items()
        ]
        # Always pass the Airflow run_id for traceability
        env_vars.append(EnvironmentVar(
            name="AIRFLOW_RUN_ID",
            value=str(context.get("run_id", "unknown"))
        ))

        log.info(
            "Starting ACA Job execution: %s/%s/%s",
            self.resource_group, self.job_name,
            {k: v for k, v in self.environment_variables.items()}
        )

        # Start the job execution
        poller = client.jobs.begin_start(
            resource_group_name=self.resource_group,
            job_name=self.job_name,
            template=JobExecutionTemplate(
                containers=[
                    JobExecutionContainer(
                        name=self.job_name,
                        env=env_vars,
                    )
                ]
            ) if env_vars else None,
        )

        # Get execution name from the result
        result = poller.result()
        execution_name = result.name
        log.info("Job execution started: %s", execution_name)

        # Poll until completion
        start_time = time.time()
        while True:
            elapsed = time.time() - start_time
            if elapsed > self.timeout:
                raise TimeoutError(
                    f"ACA Job {self.job_name} execution {execution_name} "
                    f"did not complete within {self.timeout}s"
                )

            execution = client.job_executions.get(
                resource_group_name=self.resource_group,
                job_name=self.job_name,
                job_execution_name=execution_name,
            )

            status = execution.status
            log.info(
                "Job %s status: %s (elapsed: %.0fs)",
                execution_name, status, elapsed
            )

            if status == "Succeeded":
                log.info("✅ ACA Job execution completed successfully: %s", execution_name)
                return execution_name

            elif status in ("Failed", "Stopped", "Degraded"):
                raise RuntimeError(
                    f"ACA Job execution {execution_name} failed with status: {status}. "
                    f"Check Azure Portal or: az containerapp job execution show "
                    f"--name {self.job_name} --resource-group {self.resource_group} "
                    f"--job-execution-name {execution_name}"
                )

            time.sleep(self.poll_interval)
