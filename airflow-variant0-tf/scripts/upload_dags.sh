#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/upload_dags.sh <resource_group> <storage_account> <share_name> <local_dags_dir>
#
# Example:
#   RG=$(terraform output -raw resource_group)
#   SA=<yourStorageAccountName>
#   SHARE=airflowdags
#   ./scripts/upload_dags.sh "$RG" "$SA" "$SHARE" "./dags"

RG="${1:?resource_group required}"
SA="${2:?storage_account required}"
SHARE="${3:?share_name required}"
LOCAL_DIR="${4:-./dags}"

if [[ ! -d "$LOCAL_DIR" ]]; then
  echo "Local DAG directory not found: $LOCAL_DIR" >&2
  exit 1
fi

echo "Getting storage account key..."
KEY="$(az storage account keys list -g "$RG" -n "$SA" --query "[0].value" -o tsv)"

echo "Ensuring share exists: $SHARE"
az storage share create --account-name "$SA" --account-key "$KEY" --name "$SHARE" >/dev/null

echo "Uploading DAG files from: $LOCAL_DIR"
# Upload each file (keeps it simple; for nested dirs you can extend)
shopt -s nullglob
FILES=("$LOCAL_DIR"/*)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No files found in $LOCAL_DIR" >&2
  exit 1
fi

for f in "${FILES[@]}"; do
  base="$(basename "$f")"
  echo " - $base"
  az storage file upload \
    --account-name "$SA" \
    --account-key "$KEY" \
    --share-name "$SHARE" \
    --source "$f" \
    --path "$base" >/dev/null
done

echo "Done. DAGs uploaded to Azure Files share '$SHARE'."