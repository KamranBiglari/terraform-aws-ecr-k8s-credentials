output "iam_user_name" {
  description = "Name of the IAM user created for ECR access"
  value       = module.ecr_credentials.iam_user_name
}

output "iam_user_arn" {
  description = "ARN of the IAM user"
  value       = module.ecr_credentials.iam_user_arn
}

output "kubernetes_namespace" {
  description = "Kubernetes namespace where ECR updater is deployed"
  value       = module.ecr_credentials.kubernetes_namespace
}

output "cronjob_name" {
  description = "Name of the CronJob"
  value       = module.ecr_credentials.cronjob_name
}

output "ecr_registry_url" {
  description = "ECR registry URL"
  value       = module.ecr_credentials.ecr_registry_url
}

output "secret_name" {
  description = "Name of the docker-registry secret"
  value       = module.ecr_credentials.secret_name
}
