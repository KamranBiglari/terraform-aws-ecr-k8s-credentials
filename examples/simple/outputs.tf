output "ecr_registry_url" {
  description = "ECR registry URL"
  value       = module.ecr_credentials.ecr_registry_url
}

output "secret_name" {
  description = "Name of the docker-registry secret"
  value       = module.ecr_credentials.secret_name
}
