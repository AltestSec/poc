#!/usr/bin/env bash
# ============================================================
# entrypoint.sh - Airflow component entrypoint
# Handles database initialization for scheduler
# ============================================================
set -e

COMPONENT="${1:-scheduler}"

echo "=========================================="
echo "Starting Airflow $COMPONENT"
echo "Airflow version: $(python -c 'import airflow; print(airflow.__version__)' 2>/dev/null || echo 'unknown')"
echo "=========================================="

# Only scheduler should initialize the database
if [ "$COMPONENT" = "scheduler" ]; then
  echo "Checking database connection..."
  
  # Wait for database to be ready
  echo "Waiting for PostgreSQL to be ready..."
  timeout 60 bash -c 'until airflow db check 2>/dev/null; do echo "Waiting for database..."; sleep 2; done' || {
    echo "⚠️  Database not ready after 60 seconds, attempting to initialize anyway..."
    airflow db init || {
      echo "❌ Database initialization failed!"
      echo "Connection string (masked): ${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN//:[^@]*@/:****@}"
      exit 1
    }
  }
  
  echo "✅ Database is ready"
  
  # Check if database needs upgrade
  echo "Checking for pending migrations..."
  airflow db check-migrations || {
    echo "Running database migrations..."
    airflow db migrate
  }
  
  # Create default admin user if it doesn't exist
  echo "Checking for admin user..."
  airflow users list 2>/dev/null | grep -q admin || {
    echo "Creating default admin user..."
    airflow users create \
      --username admin \
      --firstname Admin \
      --lastname User \
      --role Admin \
      --email admin@example.com \
      --password admin 2>/dev/null || echo "⚠️  Admin user creation failed (may already exist)"
    echo "⚠️  Default admin user created with password 'admin' - CHANGE THIS IMMEDIATELY!"
  }
  
  echo "✅ Database initialization completed"
fi

echo "Starting $COMPONENT..."
echo "Command: airflow $@"
exec airflow "$@"
