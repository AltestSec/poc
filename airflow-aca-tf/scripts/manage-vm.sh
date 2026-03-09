#!/bin/bash
# ============================================================
# Manage Windows VM
# Start, stop, connect to Windows jump box
# ============================================================
set -euo pipefail

RESOURCE_GROUP="${1:-}"
ENV_NAME="${2:-}"
ACTION="${3:-status}"

if [[ -z "$RESOURCE_GROUP" ]] || [[ -z "$ENV_NAME" ]]; then
  echo "Usage: $0 <resource-group> <env-name> [action]"
  echo ""
  echo "Actions:"
  echo "  status   - Show VM status (default)"
  echo "  start    - Start VM"
  echo "  stop     - Stop VM (deallocate to save money)"
  echo "  restart  - Restart VM"
  echo "  connect  - Get RDP connection info"
  echo "  ip       - Get public IP"
  echo ""
  echo "Example: $0 merzlikin-tf-state-rg airflow-poc start"
  exit 1
fi

VM_NAME="${ENV_NAME}-vm"

# Check if VM exists
if ! az vm show --name "$VM_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "✗ VM not found: $VM_NAME"
  echo ""
  echo "To enable VM, set in terraform.tfvars:"
  echo "  enable_windows_vm = true"
  echo "  vm_admin_password = \"YourPassword123!\""
  echo ""
  echo "Then run: terraform apply"
  exit 1
fi

case "$ACTION" in
  status)
    echo "═══════════════════════════════════════════════"
    echo " VM Status"
    echo "═══════════════════════════════════════════════"
    
    STATUS=$(az vm get-instance-view \
      --name "$VM_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv)
    
    PUBLIC_IP=$(az network public-ip show \
      --name "${VM_NAME}-pip" \
      --resource-group "$RESOURCE_GROUP" \
      --query "ipAddress" -o tsv 2>/dev/null || echo "N/A")
    
    PRIVATE_IP=$(az vm show \
      --name "$VM_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query "privateIps" -o tsv)
    
    echo "VM Name:     $VM_NAME"
    echo "Status:      $STATUS"
    echo "Public IP:   $PUBLIC_IP"
    echo "Private IP:  $PRIVATE_IP"
    echo ""
    
    if [[ "$STATUS" == "VM running" ]]; then
      echo "✓ VM is running"
      echo ""
      echo "Connect with: $0 $RESOURCE_GROUP $ENV_NAME connect"
    elif [[ "$STATUS" == "VM deallocated" ]]; then
      echo "⚠ VM is stopped (deallocated)"
      echo ""
      echo "Start with: $0 $RESOURCE_GROUP $ENV_NAME start"
    else
      echo "Status: $STATUS"
    fi
    ;;
    
  start)
    echo "▶ Starting VM: $VM_NAME"
    az vm start --name "$VM_NAME" --resource-group "$RESOURCE_GROUP"
    echo "✓ VM started"
    echo ""
    $0 "$RESOURCE_GROUP" "$ENV_NAME" connect
    ;;
    
  stop)
    echo "▶ Stopping VM: $VM_NAME"
    echo "⚠ This will deallocate the VM to save costs"
    az vm deallocate --name "$VM_NAME" --resource-group "$RESOURCE_GROUP"
    echo "✓ VM stopped (deallocated)"
    echo ""
    echo "Cost savings: ~$30/month while stopped"
    echo "Start again with: $0 $RESOURCE_GROUP $ENV_NAME start"
    ;;
    
  restart)
    echo "▶ Restarting VM: $VM_NAME"
    az vm restart --name "$VM_NAME" --resource-group "$RESOURCE_GROUP"
    echo "✓ VM restarted"
    ;;
    
  connect)
    PUBLIC_IP=$(az network public-ip show \
      --name "${VM_NAME}-pip" \
      --resource-group "$RESOURCE_GROUP" \
      --query "ipAddress" -o tsv)
    
    echo "═══════════════════════════════════════════════"
    echo " RDP Connection Info"
    echo "═══════════════════════════════════════════════"
    echo "Public IP:  $PUBLIC_IP"
    echo "Username:   azureuser"
    echo "Password:   (the one you set in terraform.tfvars)"
    echo ""
    echo "Windows: mstsc /v:$PUBLIC_IP"
    echo "macOS:   Use Microsoft Remote Desktop app"
    echo "Linux:   rdesktop $PUBLIC_IP -u azureuser"
    echo ""
    echo "After connecting:"
    echo "1. Wait for Docker Desktop to install (first login)"
    echo "2. Restart VM"
    echo "3. Start Docker Desktop"
    echo "4. Open PowerShell and run: az login"
    echo "5. Build images: See WINDOWS_VM_GUIDE.md"
    ;;
    
  ip)
    PUBLIC_IP=$(az network public-ip show \
      --name "${VM_NAME}-pip" \
      --resource-group "$RESOURCE_GROUP" \
      --query "ipAddress" -o tsv)
    echo "$PUBLIC_IP"
    ;;
    
  *)
    echo "✗ Unknown action: $ACTION"
    echo "Valid actions: status, start, stop, restart, connect, ip"
    exit 1
    ;;
esac
