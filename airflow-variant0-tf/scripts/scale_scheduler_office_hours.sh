#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/scale_scheduler_office_hours.sh <resource_group> <scheduler_app_name> on|off
#
# Example:
#   RG=$(terraform output -raw resource_group)
#   SCH="poc-airflow-sch"
#   ./scripts/scale_scheduler_office_hours.sh "$RG" "$SCH" off   # stop at night
#   ./scripts/scale_scheduler_office_hours.sh "$RG" "$SCH" on    # start in morning

RG="${1:?resource_group required}"
SCHEDULER_APP="${2:?scheduler container app name required}"
MODE="${3:?mode on|off required}"

# Ensure extension exists
if ! az extension show --name containerapp >/dev/null 2>&1; then
  echo "Azure CLI extension 'containerapp' not found, installing..."
  az extension add --name containerapp >/dev/null
fi

case "$MODE" in
  off)
    echo "Scaling scheduler OFF (min-replicas=0, max-replicas=0): $SCHEDULER_APP"
    az containerapp update -g "$RG" -n "$SCHEDULER_APP" --min-replicas 0 --max-replicas 0 >/dev/null
    ;;
  on)
    echo "Scaling scheduler ON (min-replicas=1, max-replicas=1): $SCHEDULER_APP"
    az containerapp update -g "$RG" -n "$SCHEDULER_APP" --min-replicas 1 --max-replicas 1 >/dev/null
    ;;
  *)
    echo "Unknown mode: $MODE (expected on|off)" >&2
    exit 1
    ;;
esac

echo "Done."