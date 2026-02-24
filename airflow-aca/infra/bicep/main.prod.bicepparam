using './main.bicep'

param envName                 = 'airflow-prod'
param location                = 'westeurope'
param deploymentMode          = 'production'
param airflowImage            = 'myacr.azurecr.io/airflow:2.9.3'
param etlRunnerImage          = 'myacr.azurecr.io/etl-runner:latest'
param acrLoginServer          = 'myacr.azurecr.io'
param airflowFernetKey        = readEnvironmentVariable('AIRFLOW_FERNET_KEY')
param airflowWebserverSecretKey = readEnvironmentVariable('AIRFLOW_SECRET_KEY')
