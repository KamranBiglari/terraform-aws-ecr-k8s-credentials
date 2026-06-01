variable "prefix" {
  description = "Prefix to be used for naming resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region where ECR repositories are located. If not provided, uses the current region from the AWS provider"
  type        = string
  default     = null
}

variable "create_iam_user" {
  description = "Whether to create IAM user for ECR access"
  type        = bool
  default     = true
}

variable "iam_user_name" {
  description = "Name of the IAM user to create for ECR access"
  type        = string
  default     = ""
}

variable "iam_user_policy_name" {
  description = "Name of the IAM user policy for ECR access"
  type        = string
  default     = ""
}

variable "create_kubernetes_resources" {
  description = "Whether to create Kubernetes resources (namespace, service account, RBAC, cronjob)"
  type        = bool
  default     = true
}

variable "iam_user_path" {
  description = "Path for IAM user"
  type        = string
  default     = "/system/"
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace for ECR credential updater"
  type        = string
  default     = "ecr-updater"
}

variable "cronjob_schedule" {
  description = "Cron schedule for ECR credential refresh (default: every 6 hours)"
  type        = string
  default     = "0 */6 * * *"
}

variable "cronjob_image" {
  description = "Docker image to use for the credential refresh cronjob"
  type        = string
  default     = "kamranbiglari/ecr-k8s-updater:latest"
}

variable "cronjob_cpu_limit" {
  description = "CPU limit for the cronjob container"
  type        = string
  default     = "100m"
}

variable "cronjob_memory_limit" {
  description = "Memory limit for the cronjob container"
  type        = string
  default     = "128Mi"
}

variable "cronjob_cpu_request" {
  description = "CPU request for the cronjob container"
  type        = string
  default     = "50m"
}

variable "cronjob_memory_request" {
  description = "Memory request for the cronjob container"
  type        = string
  default     = "64Mi"
}

variable "successful_jobs_history_limit" {
  description = "Number of successful jobs to keep in history"
  type        = number
  default     = 3
}

variable "failed_jobs_history_limit" {
  description = "Number of failed jobs to keep in history"
  type        = number
  default     = 3
}

variable "secret_name" {
  description = "Name of the docker-registry secret to create in each namespace"
  type        = string
  default     = "ecr-registry-credentials"
}

variable "target_namespaces" {
  description = "Space-separated list of Kubernetes namespaces to update. If empty, will discover all namespaces using kubectl"
  type        = string
  default     = ""
}

variable "exclude_namespaces" {
  description = "Space-separated list of Kubernetes namespaces to skip when updating secrets"
  type        = string
  default     = "kube-public"
}

variable "cronjob_image_pull_policy" {
  description = "Image pull policy for the cronjob/bootstrap container. Use 'Always' if you track a mutable tag like ':latest'"
  type        = string
  default     = "IfNotPresent"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.cronjob_image_pull_policy)
    error_message = "cronjob_image_pull_policy must be one of: Always, IfNotPresent, Never."
  }
}

variable "cronjob_concurrency_policy" {
  description = "How to treat concurrent executions of the CronJob (Allow, Forbid, or Replace)"
  type        = string
  default     = "Forbid"

  validation {
    condition     = contains(["Allow", "Forbid", "Replace"], var.cronjob_concurrency_policy)
    error_message = "cronjob_concurrency_policy must be one of: Allow, Forbid, Replace."
  }
}

variable "cronjob_starting_deadline_seconds" {
  description = "Deadline in seconds for starting a job if it misses its scheduled time"
  type        = number
  default     = 900
}

variable "create_bootstrap_job" {
  description = "Whether to create a one-shot Job that populates ECR credentials immediately on apply, instead of waiting for the first CronJob run"
  type        = bool
  default     = true
}

variable "bootstrap_job_wait_for_completion" {
  description = "Whether Terraform should wait for the bootstrap Job to complete during apply"
  type        = bool
  default     = true
}

variable "bootstrap_job_ttl_seconds" {
  description = "TTL in seconds after which the finished bootstrap Job is automatically cleaned up"
  type        = number
  default     = 900
}

variable "tags" {
  description = "Additional tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID (if not creating IAM user). Leave empty if create_iam_user is true"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key (if not creating IAM user). Leave empty if create_iam_user is true"
  type        = string
  default     = ""
  sensitive   = true
}
