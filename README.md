# AWS ECR Kubernetes Credentials Terraform Module

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Provider-FF9900?logo=amazon-aws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Provider-326CE5?logo=kubernetes)](https://registry.terraform.io/providers/hashicorp/kubernetes/latest)

A Terraform module to automate AWS ECR credential refresh in Kubernetes clusters. This module solves the problem of ECR authentication tokens expiring every 12 hours by deploying a CronJob that automatically refreshes credentials across all namespaces.

## Features

- ✅ **Automated credential refresh** - Runs every 6 hours (configurable) to keep credentials fresh
- ✅ **Multi-namespace support** - Automatically updates secrets in all namespaces
- ✅ **Flexible IAM management** - Create IAM user or use existing credentials
- ✅ **Customizable resources** - Configure CPU/memory limits, schedule, and more
- ✅ **Production-ready** - Includes RBAC, proper service accounts, and minimal permissions
- ✅ **Works with any Kubernetes** - Not limited to EKS; supports self-hosted clusters

## Prerequisites

- Terraform >= 1.0
- AWS Provider >= 4.0
- Kubernetes Provider >= 2.0
- Kubernetes cluster with appropriate credentials configured
- AWS account with ECR repositories

## Usage

### Basic Example

```hcl
module "ecr_credentials" {
  source = "KamranBiglari/ecr-k8s-credentials/aws"

  prefix     = "myapp"
  aws_region = "us-east-1"
}
```

### Complete Example with Custom Configuration

```hcl
module "ecr_credentials" {
  source = "KamranBiglari/ecr-k8s-credentials/aws"

  prefix     = "myapp"
  aws_region = "us-east-1"

  # IAM Configuration
  create_iam_user = true
  iam_user_path   = "/service/"

  # Kubernetes Configuration
  create_kubernetes_resources = true
  kubernetes_namespace        = "ecr-updater"

  # CronJob Configuration
  cronjob_schedule              = "0 */6 * * *"  # Every 6 hours
  cronjob_image                 = "kamranbiglari/ecr-k8s-updater:v0.1.0"
  cronjob_image_pull_policy     = "IfNotPresent"
  cronjob_concurrency_policy    = "Forbid"
  successful_jobs_history_limit = 3
  failed_jobs_history_limit     = 3

  # Namespace targeting
  # target_namespaces  = "default app-prod"  # leave empty to discover all
  exclude_namespaces = "kube-public kube-node-lease"

  # Resource Limits
  cronjob_cpu_limit      = "100m"
  cronjob_memory_limit   = "128Mi"
  cronjob_cpu_request    = "50m"
  cronjob_memory_request = "64Mi"

  # Secret Configuration
  secret_name = "ecr-registry-credentials"

  # Tags
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "myapp"
  }
}
```

### Using Existing IAM Credentials

If you already have AWS credentials and don't want to create a new IAM user:

```hcl
module "ecr_credentials" {
  source = "KamranBiglari/ecr-k8s-credentials/aws"

  prefix     = "myapp"
  aws_region = "us-east-1"

  # Use existing credentials
  create_iam_user        = false
  aws_access_key_id      = var.existing_aws_access_key
  aws_secret_access_key  = var.existing_aws_secret_key
}
```

### Only Create IAM Resources

If you want to manage Kubernetes resources separately:

```hcl
module "ecr_credentials" {
  source = "KamranBiglari/ecr-k8s-credentials/aws"

  prefix     = "myapp"
  aws_region = "us-east-1"

  create_iam_user             = true
  create_kubernetes_resources = false
}
```

## How It Works

1. **IAM User** - Creates an IAM user with read-only ECR permissions
2. **Kubernetes Namespace** - Deploys a dedicated namespace for the credential updater
3. **Service Account + RBAC** - Sets up proper permissions to update secrets cluster-wide
4. **Bootstrap Job** - Runs a one-shot Job on apply so credentials exist immediately (no waiting for the first scheduled run). Can be disabled with `create_bootstrap_job = false`.
5. **CronJob** - Runs a scheduled job that:
   - Fetches a fresh ECR token from AWS
   - Discovers all namespaces in the cluster (skipping any in `exclude_namespaces`)
   - Creates/updates docker-registry secrets in each namespace
6. **Secret Storage** - AWS credentials are stored securely in Kubernetes secrets

The credential-refresh pods run hardened: non-root (UID 1000), read-only root filesystem, no privilege escalation, and all Linux capabilities dropped.

```
┌──────────────────────┐
│  Bootstrap Job        │ (Runs once, on apply)
│  + CronJob            │ (Runs every 6 hours)
│  ecr-k8s-updater      │
└──────────┬───────────┘
           │
           ├─> Fetches ECR token from AWS
           │
           ├─> Discovers all namespaces (minus excluded)
           │
           └─> Creates/Updates docker-registry secret
               in each namespace
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prefix | Prefix for naming resources | `string` | n/a | yes |
| aws_region | AWS region where ECR repositories are located. If not set, uses the provider's current region | `string` | `null` | no |
| create_iam_user | Whether to create IAM user for ECR access | `bool` | `true` | no |
| iam_user_name | Name of the IAM user to create | `string` | `""` | no |
| iam_user_policy_name | Name of the IAM user policy | `string` | `""` | no |
| create_kubernetes_resources | Whether to create Kubernetes resources | `bool` | `true` | no |
| iam_user_path | Path for IAM user | `string` | `"/system/"` | no |
| kubernetes_namespace | Kubernetes namespace for ECR credential updater | `string` | `"ecr-updater"` | no |
| cronjob_schedule | Cron schedule for ECR credential refresh | `string` | `"0 */6 * * *"` | no |
| cronjob_image | Docker image for the credential refresh cronjob | `string` | `"kamranbiglari/ecr-k8s-updater:v0.1.0"` | no |
| cronjob_image_pull_policy | Image pull policy (`Always`, `IfNotPresent`, `Never`). Use `Always` if tracking a mutable tag like `:latest` | `string` | `"IfNotPresent"` | no |
| cronjob_concurrency_policy | Concurrency policy for the CronJob (`Allow`, `Forbid`, `Replace`) | `string` | `"Forbid"` | no |
| cronjob_starting_deadline_seconds | Deadline in seconds for starting a missed job | `number` | `900` | no |
| cronjob_cpu_limit | CPU limit for the cronjob container | `string` | `"100m"` | no |
| cronjob_memory_limit | Memory limit for the cronjob container | `string` | `"128Mi"` | no |
| cronjob_cpu_request | CPU request for the cronjob container | `string` | `"50m"` | no |
| cronjob_memory_request | Memory request for the cronjob container | `string` | `"64Mi"` | no |
| successful_jobs_history_limit | Number of successful jobs to keep in history | `number` | `3` | no |
| failed_jobs_history_limit | Number of failed jobs to keep in history | `number` | `3` | no |
| create_bootstrap_job | Run a one-shot Job to populate credentials immediately on apply | `bool` | `true` | no |
| bootstrap_job_wait_for_completion | Whether Terraform waits for the bootstrap Job to finish during apply | `bool` | `true` | no |
| bootstrap_job_ttl_seconds | TTL in seconds before the finished bootstrap Job is cleaned up | `number` | `900` | no |
| secret_name | Name of the docker-registry secret | `string` | `"ecr-registry-credentials"` | no |
| target_namespaces | Space-separated namespaces to update. If empty, discovers all via kubectl | `string` | `""` | no |
| exclude_namespaces | Space-separated namespaces to skip when updating secrets | `string` | `"kube-public"` | no |
| tags | Additional tags for AWS resources | `map(string)` | `{}` | no |
| aws_access_key_id | AWS Access Key ID (if not creating IAM user) | `string` | `""` | no |
| aws_secret_access_key | AWS Secret Access Key (if not creating IAM user) | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| iam_user_name | Name of the IAM user created for ECR access |
| iam_user_arn | ARN of the IAM user created for ECR access |
| iam_access_key_id | Access key ID for the IAM user (sensitive) |
| iam_secret_access_key | Secret access key for the IAM user (sensitive) |
| kubernetes_namespace | Kubernetes namespace where ECR updater resources are deployed |
| kubernetes_service_account | Name of the Kubernetes service account |
| cronjob_name | Name of the Kubernetes CronJob |
| ecr_registry_url | ECR registry URL |
| aws_account_id | AWS Account ID |
| secret_name | Name of the docker-registry secret created in each namespace |

## Using the Credentials

After deploying this module, your Kubernetes pods can use the ECR credentials by referencing the secret in their pod specifications:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: my-container
    image: <account-id>.dkr.ecr.<region>.amazonaws.com/my-repo:latest
  imagePullSecrets:
  - name: ecr-registry-credentials  # matches var.secret_name / the secret_name output
```

## Security Considerations

- **IAM Permissions**: The IAM user has read-only access to ECR
- **Kubernetes RBAC**: The service account can only manage secrets and list namespaces
- **Secret Storage**: AWS credentials are stored in Kubernetes secrets (consider using external secret managers for enhanced security)
- **Token Rotation**: Tokens are refreshed every 6 hours (configurable), well before the 12-hour expiration

## Monitoring and Troubleshooting

### Check CronJob Status

```bash
kubectl get cronjobs -n ecr-updater
kubectl get jobs -n ecr-updater
```

### View Logs

```bash
# Get the latest job
kubectl get jobs -n ecr-updater --sort-by=.metadata.creationTimestamp

# View logs
kubectl logs -n ecr-updater job/<job-name>
```

### Manually Trigger the Job

```bash
kubectl create job --from=cronjob/ecr-credential-refresh manual-refresh-$(date +%s) -n ecr-updater
```

### Verify Secrets

```bash
# List secrets in all namespaces
kubectl get secrets --all-namespaces | grep ecr-registry-credentials

# Inspect a specific secret
kubectl get secret ecr-registry-credentials -n default -o yaml
```

## Examples

See the [examples](./examples/) directory for complete working examples:

- [Complete Example](./examples/complete/) - Full configuration with all options

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This module is licensed under the MIT License. See [LICENSE](./LICENSE) for more information.

## Author

Created and maintained by [Kamran Biglari](https://github.com/KamranBiglari)

## Acknowledgments

This module was inspired by the need for a simple, reliable solution for ECR credential management in self-hosted Kubernetes clusters running outside of AWS infrastructure.
