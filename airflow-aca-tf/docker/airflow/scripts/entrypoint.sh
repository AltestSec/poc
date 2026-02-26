#!/bin/bash
# ============================================================
# entrypoint.sh - Airflow component entrypoint
# Handles database initialization for scheduler
# ============================================================
set -e

COMPONENT="${1:-scheduler}"

echo "=========================================="
echo "Starting Airflow $COMPONENT"
echo "=========================================="

# Only scheduler should initialize the database
if [ "$COMPONENT" = "scheduler" ]; then
  echo "Checking database connection..."
  
  # Wait for database to be ready
  timeout 60 bash -c 'until airflow db check 2>/dev/null; do echo "Waiting for database..."; sleep 2; done' || {
    echo "Database not ready, attempting to initialize..."
    airflow db init
  }
  
  echo "Database is ready"
  
  # Check if database needs upgrade
  airflow db check-migrations || {
    echo "Running database migrations..."
    airflow db migrate
  }
  
  # Create default admin user if it doesn't exist
  airflow users list | grep -q admin || {
    echo "Creating default admin user..."
    airflow users create \
      --username admin \
      --firstname Admin \
      --lastname User \
      --role Admin \
      --email admin@example.com \
      --password admin
    echo "⚠️  Default admin user created with password 'admin' - CHANGE THIS IMMEDIATELY!"
  }
fi

echo "Starting $COMPONENT..."
exec airflow "$@"
