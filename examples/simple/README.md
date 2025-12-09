# Simple Example

This example demonstrates the minimal configuration needed to use the AWS ECR Kubernetes Credentials module.

## Usage

1. Update the Kubernetes provider configuration in `provider.tf` if needed
2. Initialize and apply:

```bash
terraform init
terraform plan
terraform apply
```

## What This Creates

With just two required variables, this module will:
- Create an IAM user with ECR read-only permissions
- Deploy a namespace called `ecr-updater` in your Kubernetes cluster
- Create a CronJob that runs every 6 hours
- Automatically update ECR credentials in all namespaces

## Verification

```bash
# Check the cronjob
kubectl get cronjob -n ecr-updater

# View recent executions
kubectl get jobs -n ecr-updater

# Check secrets in your namespaces
kubectl get secrets --all-namespaces | grep ecr-registry-credentials
```

## Using the Credentials

In your pod specifications, reference the secret:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: my-container
    image: <account-id>.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest
  imagePullSecrets:
  - name: ecr-registry-credentials
```

## Cleanup

```bash
terraform destroy
```
