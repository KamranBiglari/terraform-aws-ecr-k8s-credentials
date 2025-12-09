# Complete Example

This example demonstrates the full configuration of the AWS ECR Kubernetes Credentials module with all available options.

## Usage

1. Update the `provider.tf` file to match your Kubernetes cluster configuration
2. Customize variables in `variables.tf` or create a `terraform.tfvars` file
3. Initialize and apply:

```bash
terraform init
terraform plan
terraform apply
```

## Configuration

This example includes:
- IAM user creation with ECR read-only permissions
- Kubernetes namespace for the credential updater
- CronJob that runs every 6 hours
- Service account with proper RBAC permissions
- Resource limits for the cronjob
- Custom tags for AWS resources

## Verification

After applying, verify the deployment:

```bash
# Check the namespace
kubectl get namespace ecr-updater

# Check the cronjob
kubectl get cronjob -n ecr-updater

# Check recent jobs
kubectl get jobs -n ecr-updater

# Manually trigger the job to test
kubectl create job --from=cronjob/ecr-credential-refresh test-$(date +%s) -n ecr-updater

# View logs
kubectl logs -n ecr-updater -l app=ecr-credential-refresh --tail=100
```

## Verify Secrets in Namespaces

```bash
# List all secrets named ecr-registry-credentials
kubectl get secrets --all-namespaces | grep ecr-registry-credentials

# Test pulling from ECR
kubectl run test-pod --image=<your-account-id>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag> \
  --image-pull-secrets=ecr-registry-credentials
```

## Cleanup

```bash
terraform destroy
```

## Customization

To customize this example:

1. **Change the schedule**: Modify `cronjob_schedule` in `main.tf`
2. **Adjust resources**: Update CPU/memory limits and requests
3. **Use existing credentials**: Set `create_iam_user = false` and provide credentials
4. **Change namespace**: Update `kubernetes_namespace` variable
