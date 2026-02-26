# Pipeline Approval Setup

The unified pipeline uses Azure DevOps **Environments** to enforce manual approvals before critical operations.

## Environments Used

The pipeline references these environments (they need to be created in Azure DevOps):

1. **`poc-infra`** / **`prod-infra`** - Terraform Apply operations
2. **`poc-destroy`** / **`prod-destroy`** - Terraform Destroy operations  
3. **`poc-apps`** / **`prod-apps`** - Application deployments

## Setup Instructions

### 1. Create Environments

In Azure DevOps:
1. Go to **Pipelines** → **Environments**
2. Click **New environment**
3. Create each environment:
   - `poc-infra`
   - `poc-destroy`
   - `poc-apps`
   - `prod-infra`
   - `prod-destroy`
   - `prod-apps`

### 2. Configure Approvals

For each environment:
1. Click on the environment name
2. Click the **⋮** menu → **Approvals and checks**
3. Click **+** → **Approvals**
4. Add approvers (users or groups)
5. Configure settings:
   - **Approvers**: Select users/groups who can approve
   - **Timeout**: How long to wait for approval (default: 30 days)
   - **Instructions**: Optional message shown to approvers

### 3. Recommended Approval Strategy

| Environment | Approvers | Timeout | Notes |
|-------------|-----------|---------|-------|
| `poc-infra` | Team leads | 7 days | Review Terraform plan before apply |
| `poc-destroy` | Team leads + Manager | 7 days | Extra caution for destroy |
| `poc-apps` | Team leads | 3 days | Review deployment readiness |
| `prod-infra` | Managers + Ops | 14 days | Production infra changes |
| `prod-destroy` | Managers + Ops | 14 days | Critical - requires multiple approvers |
| `prod-apps` | Managers + Ops | 7 days | Production deployments |

### 4. Additional Checks (Optional)

You can add other checks to environments:
- **Branch control** - Only allow deployments from specific branches (e.g., `main` for prod)
- **Business hours** - Only allow deployments during business hours
- **Invoke Azure Function** - Custom validation logic
- **Invoke REST API** - External approval systems

## How It Works

When the pipeline reaches a deployment job with an environment:

1. Pipeline pauses and shows **"Waiting for approval"**
2. Approvers receive notification (email/Teams if configured)
3. Approvers can:
   - **Review** the Terraform plan (published as artifact)
   - **Approve** to continue
   - **Reject** to stop the pipeline
4. Pipeline continues or fails based on approval decision

## Viewing Pending Approvals

- **Pipelines** → **Environments** → Click environment → **Pending approvals** tab
- Or click the notification link in the pipeline run

## Best Practices

1. **Always review the plan artifact** before approving Terraform Apply
2. **Use multiple approvers** for production and destroy operations
3. **Set reasonable timeouts** to avoid stale approvals
4. **Document approval criteria** in the environment instructions
5. **Use branch control** to prevent accidental prod deployments from feature branches

## Bypassing Approvals (Development)

If you want to skip approvals for POC/dev:
- Don't configure approval checks on `poc-*` environments
- Or create separate environments like `poc-auto` without approvals
