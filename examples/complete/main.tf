# Complete example with all configuration options

module "ecr_credentials" {
  source = "../.."

  # Required variables
  prefix     = var.prefix
  aws_region = var.aws_region

  # IAM Configuration
  create_iam_user = true
  iam_user_path   = "/service/"

  # Kubernetes Configuration
  create_kubernetes_resources = true
  kubernetes_namespace        = "ecr-updater"

  # CronJob Configuration
  cronjob_schedule              = "0 */6 * * *" # Every 6 hours
  cronjob_image                 = "alpine/k8s:1.30.7"
  successful_jobs_history_limit = 3
  failed_jobs_history_limit     = 3

  # Resource Limits
  cronjob_cpu_limit      = "100m"
  cronjob_memory_limit   = "128Mi"
  cronjob_cpu_request    = "50m"
  cronjob_memory_request = "64Mi"

  # Secret Configuration
  secret_name = "ecr-registry-credentials"

  # Tags
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.prefix
    Example     = "complete"
  }
}
