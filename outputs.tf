output "iam_user_name" {
  description = "Name of the IAM user created for ECR access"
  value       = var.create_iam_user ? aws_iam_user.ecr_k8s_user[0].name : null
}

output "iam_user_arn" {
  description = "ARN of the IAM user created for ECR access"
  value       = var.create_iam_user ? aws_iam_user.ecr_k8s_user[0].arn : null
}

output "iam_access_key_id" {
  description = "Access key ID for the IAM user"
  value       = var.create_iam_user ? aws_iam_access_key.ecr_k8s_key[0].id : null
  sensitive   = true
}

output "iam_secret_access_key" {
  description = "Secret access key for the IAM user"
  value       = var.create_iam_user ? aws_iam_access_key.ecr_k8s_key[0].secret : null
  sensitive   = true
}

output "kubernetes_namespace" {
  description = "Kubernetes namespace where ECR updater resources are deployed"
  value       = var.create_kubernetes_resources ? kubernetes_namespace_v1.ecr_updater[0].metadata[0].name : null
}

output "kubernetes_service_account" {
  description = "Name of the Kubernetes service account for ECR credential updater"
  value       = var.create_kubernetes_resources ? kubernetes_service_account_v1.ecr_updater[0].metadata[0].name : null
}

output "cronjob_name" {
  description = "Name of the Kubernetes CronJob for ECR credential refresh"
  value       = var.create_kubernetes_resources ? kubernetes_cron_job_v1.ecr_credential_refresh[0].metadata[0].name : null
}

output "ecr_registry_url" {
  description = "ECR registry URL"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region != null ? var.aws_region : data.aws_region.current.name}.amazonaws.com"
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "secret_name" {
  description = "Name of the docker-registry secret created in each namespace"
  value       = var.secret_name
}
