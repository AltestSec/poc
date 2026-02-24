using './main.bicep'

param envName                 = 'airflow-poc'
param location                = 'westeurope'
param deploymentMode          = 'poc'
param airflowImage            = 'apache/airflow:2.9.3'
param etlRunnerImage          = 'ghcr.io/your-org/etl-runner:latest'
param acrLoginServer          = ''               // leave empty if using public images
param airflowFernetKey        = readEnvironmentVariable('AIRFLOW_FERNET_KEY')
param airflowWebserverSecretKey = readEnvironmentVariable('AIRFLOW_SECRET_KEY')
