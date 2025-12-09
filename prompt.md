@ -0,0 +1,508 @@
# Automating AWS ECR Credential Refresh in Kubernetes with Terraform

## The Problem: ECR Tokens That Expire Every 12 Hours

If you're running a Kubernetes cluster and pulling Docker images from AWS Elastic Container Registry (ECR), you've likely encountered this frustrating problem: **ECR authentication tokens expire every 12 hours**.

This means your pods can't pull images after the token expires, leading to failed deployments and restarts. While this is a security feature by design, it creates an operational headache for teams running production Kubernetes clusters.

## Common Solutions and Their Limitations

Several approaches exist to solve this problem:

1. **Manual token refresh** — Not practical for production environments
2. **AWS EKS with IRSA** — Great if you're on EKS, but what about self-hosted clusters?
3. **Third-party tools** — Adds another dependency to manage
4. **Custom operators** — Overkill for a relatively simple problem

For my self-hosted Kubernetes cluster (running on Hetzner Cloud with Talos Linux), I needed a simple, reliable solution that would work outside of AWS infrastructure.

## The Solution: A Kubernetes CronJob with Terraform

I built an automated ECR credential refresh system using Terraform that:

- ✅ Runs every 6 hours (well before the 12-hour expiration)
- ✅ Updates credentials across **all namespaces** automatically
- ✅ Requires minimal resources (50m CPU, 64Mi RAM)
- ✅ Is fully declarative and version-controlled with Terraform
- ✅ Works with any Kubernetes cluster (not just EKS)

## Architecture Overview

The solution consists of several components:

1. **IAM User** — Dedicated AWS user for ECR read-only access
2. **Kubernetes Namespace** — Isolated namespace for the credential updater
3. **Service Account + RBAC** — Cluster-wide permissions to update secrets
4. **CronJob** — Scheduled task that refreshes credentials
5. **AWS Credentials Secret** — Securely stored AWS access keys

Here's how they work together:

```
┌─────────────────┐
│   CronJob       │ (Runs every 6 hours)
│  (alpine/k8s)   │
└────────┬────────┘
         │
         ├─> Fetches ECR token from AWS
         │
         ├─> Discovers all namespaces
         │
         └─> Creates/Updates docker-registry secret
             in each namespace
```

## Implementation Details

### Step 1: IAM User and Policy

First, create a dedicated IAM user with read-only ECR permissions:

```hcl
resource "aws_iam_user" "ecr_k8s_user" {
  name = "${var.APP_NAME}-ecr-k8s-user"
  path = "/system/"
}

resource "aws_iam_user_policy" "ecr_k8s_policy" {
  name = "${var.APP_NAME}-ecr-readonly"
  user = aws_iam_user.ecr_k8s_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_access_key" "ecr_k8s_key" {
  user = aws_iam_user.ecr_k8s_user.name
}
```

**Security Note**: These are read-only permissions. The IAM user can pull images but cannot push or modify your ECR repositories.

### Step 2: Kubernetes Namespace and Secrets

Create a dedicated namespace to isolate the credential updater:

```hcl
resource "kubernetes_namespace" "ecr_updater" {
  metadata {
    name = "ecr-updater"
    labels = {
      name = "ecr-updater"
    }
  }
}

resource "kubernetes_secret" "aws_credentials" {
  metadata {
    name      = "aws-ecr-credentials"
    namespace = kubernetes_namespace.ecr_updater.metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.ecr_k8s_key.id
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.ecr_k8s_key.secret
    AWS_REGION            = var.AWS_REGION
    AWS_ACCOUNT_ID        = data.aws_caller_identity.current.account_id
  }

  type = "Opaque"
}
```

### Step 3: RBAC Configuration

The CronJob needs cluster-wide permissions to update secrets in all namespaces:

```hcl
resource "kubernetes_service_account" "ecr_updater" {
  metadata {
    name      = "ecr-credential-updater"
    namespace = kubernetes_namespace.ecr_updater.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "ecr_updater" {
  metadata {
    name = "ecr-credential-updater"
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "create", "patch", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "ecr_updater" {
  metadata {
    name = "ecr-credential-updater"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.ecr_updater.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.ecr_updater.metadata[0].name
    namespace = kubernetes_namespace.ecr_updater.metadata[0].name
  }
}
```

### Step 4: The CronJob Magic

The heart of the solution is a CronJob that runs every 6 hours:

```hcl
resource "kubernetes_cron_job_v1" "ecr_credential_refresh" {
  metadata {
    name      = "ecr-credential-refresh"
    namespace = kubernetes_namespace.ecr_updater.metadata[0].name
  }

  spec {
    schedule                      = "0 */6 * * *" # Every 6 hours
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        name = "ecr-credential-refresh"
      }

      spec {
        template {
          metadata {
            labels = {
              app = "ecr-credential-refresh"
            }
          }

          spec {
            service_account_name = kubernetes_service_account.ecr_updater.metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name  = "ecr-credential-updater"
              image = "alpine/k8s:1.30.7"

              command = ["/bin/sh", "-c"]
              args = [
                <<-EOT
                #!/bin/sh
                set -e

                # Install AWS CLI
                echo "Installing AWS CLI..."
                apk add --no-cache aws-cli

                echo "Fetching ECR authorization token..."
                TOKEN=$(aws ecr get-login-password --region $AWS_REGION)

                echo "Creating Docker config JSON..."
                DOCKER_CONFIG=$(echo -n "{\"auths\":{\"$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com\":{\"username\":\"AWS\",\"password\":\"$TOKEN\"}}}" | base64 -w 0)

                # Get all namespaces and update secrets in each
                echo "Discovering all namespaces..."
                NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

                echo "Found namespaces: $NAMESPACES"

                for NAMESPACE in $NAMESPACES; do
                  echo "Updating secret in namespace: $NAMESPACE"

                  # Create or update the secret
                  kubectl create secret docker-registry ecr-registry-credentials \
                    --docker-server=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com \
                    --docker-username=AWS \
                    --docker-password=$TOKEN \
                    --namespace=$NAMESPACE \
                    --dry-run=client -o yaml | kubectl apply -f -

                  echo "Secret updated successfully in $NAMESPACE"
                done

                echo "ECR credentials refresh completed successfully!"
                EOT
              ]

              env {
                name = "AWS_ACCESS_KEY_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.aws_credentials.metadata[0].name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.aws_credentials.metadata[0].name
                    key  = "AWS_SECRET_ACCESS_KEY"
                  }
                }
              }

              env {
                name = "AWS_REGION"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.aws_credentials.metadata[0].name
                    key  = "AWS_REGION"
                  }
                }
              }

              env {
                name = "AWS_ACCOUNT_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.aws_credentials.metadata[0].name
                    key  = "AWS_ACCOUNT_ID"
                  }
                }
              }

              resources {
                limits = {
                  cpu    = "100m"
                  memory = "128Mi"
                }
                requests = {
                  cpu    = "50m"
                  memory = "64Mi"
                }
              }
            }
          }
        }
      }
    }
  }
}
```

## How It Works

The shell script in the CronJob performs these steps:

1. **Installs AWS CLI** in the Alpine container
2. **Fetches a fresh ECR token** using AWS credentials
3. **Discovers all namespaces** in the cluster
4. **Creates or updates** a `docker-registry` secret named `ecr-registry-credentials` in each namespace
5. **Logs progress** for debugging and monitoring

The key insight is using `kubectl apply` with `--dry-run=client -o yaml`, which allows us to create the secret if it doesn't exist or update it if it does — all in one command.

## Using the Credentials in Your Deployments

Once deployed, reference the secret in your pod specifications:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ecr-registry-credentials  # This is automatically created/updated
      containers:
        - name: my-app
          image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest
```

## Benefits of This Approach

### 1. **Infrastructure as Code**
Everything is defined in Terraform, making it reproducible and version-controlled.

### 2. **Works Everywhere**
Not tied to EKS or any specific cloud provider. Works with self-hosted clusters on Hetzner, DigitalOcean, bare metal, etc.

### 3. **Minimal Resources**
The CronJob uses only 50m CPU and 64Mi RAM — negligible overhead.

### 4. **Set It and Forget It**
Once deployed, it runs automatically every 6 hours. No manual intervention needed.

### 5. **Multi-Namespace Support**
Automatically discovers and updates credentials in all namespaces, including new ones.

### 6. **Simple Debugging**
Logs are straightforward to read. Check job history with:
```bash
kubectl get jobs -n ecr-updater
kubectl logs -n ecr-updater job/ecr-credential-refresh-xxxxx
```

## Monitoring and Troubleshooting

### Check CronJob Status
```bash
kubectl get cronjob -n ecr-updater
```

### View Job History
```bash
kubectl get jobs -n ecr-updater
```

### Check Logs
```bash
# Get the latest job
kubectl get jobs -n ecr-updater --sort-by=.metadata.creationTimestamp

# View logs
kubectl logs -n ecr-updater job/ecr-credential-refresh-12345678
```

### Verify Secrets
```bash
# Check if secrets exist in all namespaces
kubectl get secrets --all-namespaces | grep ecr-registry-credentials
```

### Manual Trigger (for testing)
```bash
kubectl create job -n ecr-updater manual-refresh --from=cronjob/ecr-credential-refresh
```

## Security Considerations

1. **IAM Permissions**: The IAM user has read-only access to ECR. It cannot push images or modify repositories.

2. **Kubernetes RBAC**: The ServiceAccount can only manage secrets and list namespaces. It has no other cluster permissions.

3. **Secret Management**: AWS credentials are stored as Kubernetes secrets. Consider using external secret management (like AWS Secrets Manager with External Secrets Operator) for enhanced security.

4. **Network Policies**: Consider adding network policies to restrict the CronJob's network access to only AWS ECR endpoints.

## Customization Options

### Change the Schedule
Modify the cron schedule to run more or less frequently:
```hcl
schedule = "0 */4 * * *"  # Every 4 hours
schedule = "0 */12 * * *" # Every 12 hours (risky - token expires every 12h)
```

### Target Specific Namespaces
Modify the shell script to only update specific namespaces:
```bash
NAMESPACES="production staging development"
```

### Different Secret Name
Change `ecr-registry-credentials` to match your existing deployments:
```bash
kubectl create secret docker-registry my-custom-secret-name \
  # ... rest of command
```

## Alternative: Initial Run Job

If you want to populate secrets immediately upon deployment (not waiting for the first CronJob run), add this Kubernetes Job:

```hcl
resource "kubernetes_job_v1" "ecr_credential_initial" {
  metadata {
    name      = "ecr-credential-initial"
    namespace = kubernetes_namespace.ecr_updater.metadata[0].name
  }

  spec {
    template {
      metadata {}
      spec {
        # ... (same spec as the CronJob)
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
    update = "5m"
  }
}
```

## Performance Considerations

The script iterates through all namespaces, which scales linearly. In my testing:

- **10 namespaces**: ~15 seconds
- **50 namespaces**: ~1 minute
- **100 namespaces**: ~2 minutes

For clusters with hundreds of namespaces, consider:
1. Filtering to only production namespaces
2. Running parallel updates
3. Increasing resource limits

## Conclusion

This Terraform-based ECR credential refresh solution has been running in my production Kubernetes cluster for months without issues. It's simple, reliable, and works across any Kubernetes distribution.

The key advantages are:
- Fully declarative infrastructure as code
- No vendor lock-in (works outside EKS)
- Minimal resource footprint
- Automatic multi-namespace support
- Easy to customize and debug

If you're running a self-hosted Kubernetes cluster and pulling from ECR, this approach can save you from expired credential headaches.

## Complete Code

The complete Terraform code is available in my infrastructure repository. Simply copy the IAM, RBAC, and CronJob resources into your existing Terraform configuration.

Key variables needed:
- `var.APP_NAME` — Your application prefix
- `var.AWS_REGION` — Your AWS region
- `var.HCLOUD_TOKEN` — Only if using Hetzner Cloud
- `data.aws_caller_identity.current.account_id` — Your AWS account ID

## Questions or Improvements?

Have you solved this problem differently? Found ways to improve this solution? I'd love to hear your thoughts in the comments!

---

**About the Author**: Building production infrastructure for cryptocurrency data feeds at scale. Passionate about Kubernetes, Terraform, and making DevOps simple and reliable.

**Tags**: #Kubernetes #AWS #ECR #Terraform #DevOps #InfrastructureAsCode #CloudNative #Docker