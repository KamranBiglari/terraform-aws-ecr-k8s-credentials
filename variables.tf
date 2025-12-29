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
