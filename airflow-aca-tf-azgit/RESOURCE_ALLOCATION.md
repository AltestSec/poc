# Airflow Resource Allocation

## Official Airflow Requirements

According to [Airflow Docker Compose documentation](https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html):

> **"You may need to configure Docker to use at least 4.00 GB of memory for the Airflow containers to run properly"**

This is the **minimum** for all Airflow containers combined.

## Current Resource Allocation

### POC Environment (Total: ~4.5GB)

| Component | CPU | Memory | Min Replicas | Max Replicas | Notes |
|-----------|-----|--------|--------------|--------------|-------|
| Scheduler | 0.75 | 1.5Gi | 1 | 1 | Needs most memory for DAG parsing |
| Webserver | 0.75 | 1.5Gi | 1 | 1 | Always running for UI access |
| Worker | 0.5 | 1Gi | 0 | 10 | Scales based on workload |
| Triggerer | 0.25 | 0.5Gi | 1 | 1 | Lightweight async tasks |
| **Total (min)** | **2.25** | **4.5Gi** | **3** | **13** | Exceeds Airflow minimum |

### Production Environment (Total: ~6.5GB)

| Component | CPU | Memory | Min Replicas | Max Replicas | Notes |
|-----------|-----|--------|--------------|--------------|-------|
| Scheduler | 1.0 | 2Gi | 2 | 2 | High availability |
| Webserver | 1.0 | 2Gi | 1 | 1 | Always running |
| Worker | 1.0 | 2Gi | 0 | 10 | More resources per task |
| Triggerer | 0.25 | 0.5Gi | 1 | 1 | Lightweight async tasks |
| **Total (min)** | **3.25** | **6.5Gi** | **4** | **14** | Production-ready |

## Why These Allocations?

### Scheduler (1.5Gi POC / 2Gi Prod)
- **Most memory-intensive component**
- Parses all DAG files
- Maintains DAG state in memory
- Schedules tasks
- Monitors task execution

**Symptoms of insufficient memory:**
- Scheduler crashes
- Slow DAG parsing
- Missed schedules
- OOMKilled errors

### Webserver (1.5Gi POC / 2Gi Prod)
- Runs Flask/Gunicorn with 4 workers
- Serves UI and REST API
- Maintains user sessions
- Renders DAG graphs

**Symptoms of insufficient memory:**
- Webserver crashes (OOMKilled exit code 137)
- Slow UI loading
- 502/504 errors
- Container restarts
- "Connection refused" errors

### Worker (1Gi POC / 2Gi Prod)
- Executes tasks
- Memory depends on task requirements
- Scales horizontally (0-10 replicas)

**Symptoms of insufficient memory:**
- Task failures
- OOMKilled during execution
- Slow task execution

### Triggerer (0.5Gi)
- Lightweight async event monitoring
- Deferrable operators
- Low resource requirements

## Cost Implications

### Azure Container Apps Pricing (Approximate)

**POC Environment (minimum replicas running):**
```
CPU: 2.25 vCPU × $0.000012/vCPU-second × 2.6M seconds/month = $70.20/month
Memory: 4.5GB × $0.000002/GB-second × 2.6M seconds/month = $23.40/month
Total: ~$94/month (minimum, no worker scaling)
```

**Production Environment (minimum replicas running):**
```
CPU: 3.25 vCPU × $0.000012/vCPU-second × 2.6M seconds/month = $101.40/month
Memory: 6.5GB × $0.000002/GB-second × 2.6M seconds/month = $33.80/month
Total: ~$135/month (minimum, no worker scaling)
```

**Note:** Workers scale to 0 when idle, so actual costs may be lower.

## Monitoring Resource Usage

### Check Current Usage

```bash
# Via management script
./scripts/manage-airflow.sh status

# Via Azure CLI
az containerapp show \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --query "properties.template.containers[0].resources"
```

### Monitor in Azure Portal

1. Go to Container Apps → Your app
2. Click "Metrics"
3. View:
   - CPU Usage
   - Memory Usage
   - Replica Count
   - Request Count

### Set Up Alerts

```bash
# Alert when memory usage > 80%
az monitor metrics alert create \
  --name airflow-high-memory \
  --resource-group merzlikin-tf-state-rg \
  --scopes <container-app-id> \
  --condition "avg UsageNanoCores > 80" \
  --description "Airflow memory usage is high"
```

## Adjusting Resources

### Increase Resources (if needed)

Edit `terraform/modules/container_apps/main.tf`:

```hcl
locals {
  scheduler_mem = "2Gi"  # Increase from 1.5Gi
  webserver_mem = "1.5Gi"  # Increase from 1Gi
  worker_mem = "2Gi"  # Increase from 1Gi
}
```

Then apply:
```bash
terraform apply -var-file=environments/poc/terraform.tfvars
```

### Decrease Resources (to save costs)

**Not recommended below these minimums:**
- Scheduler: 1Gi (absolute minimum)
- Webserver: 0.5Gi (may cause crashes)
- Worker: 0.5Gi (depends on tasks)

## Troubleshooting

### Container keeps crashing

**Check logs:**
```bash
./scripts/manage-airflow.sh logs scheduler
```

**Look for:**
- `OOMKilled` - Increase memory
- `SIGTERM` - Container killed by health check
- `Database connection failed` - Check PostgreSQL

### Slow performance

**Symptoms:**
- DAGs take long to parse
- UI is slow
- Tasks queue up

**Solutions:**
1. Increase scheduler memory
2. Increase worker replicas
3. Optimize DAG code
4. Reduce DAG parsing frequency

### High costs

**Reduce costs by:**
1. Set worker `min_replicas = 0` (already configured)
2. Use smaller SKUs for PostgreSQL/Redis
3. Schedule DAGs during off-peak hours
4. Optimize task execution time

## Best Practices

1. **Start with recommended minimums** (4GB total)
2. **Monitor resource usage** for first week
3. **Adjust based on actual usage** patterns
4. **Scale workers horizontally** not vertically
5. **Keep scheduler memory high** (most critical)
6. **Use production settings** for production workloads

## References

- [Airflow Docker Compose Guide](https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html)
- [Azure Container Apps Pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/)
- [Airflow Best Practices](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html)
