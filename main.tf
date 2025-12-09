# IAM user for ECR access (for pulling images from K8s)
resource "aws_iam_user" "ecr_k8s_user" {
  count = var.create_iam_user ? 1 : 0

  name = "${var.prefix}-ecr-k8s-user"
  path = var.iam_user_path

  tags = merge(
    {
      Name = "${var.prefix}-ecr-k8s-user"
    },
    var.tags
  )
}

# IAM policy for ECR read access
resource "aws_iam_user_policy" "ecr_k8s_policy" {
  count = var.create_iam_user ? 1 : 0

  name = "${var.prefix}-ecr-readonly"
  user = aws_iam_user.ecr_k8s_user[0].name

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
  count = var.create_iam_user ? 1 : 0

  user = aws_iam_user.ecr_k8s_user[0].name
}

# Create a namespace for the ECR credential refresh job
resource "kubernetes_namespace_v1" "ecr_updater" {
  count = var.create_kubernetes_resources ? 1 : 0

  metadata {
    name = var.kubernetes_namespace
    labels = {
      name = var.kubernetes_namespace
    }
  }
}

# Create a secret with AWS credentials for the CronJob
resource "kubernetes_secret_v1" "aws_credentials" {
  count = var.create_kubernetes_resources ? 1 : 0

  metadata {
    name      = "aws-ecr-credentials"
    namespace = kubernetes_namespace_v1.ecr_updater[0].metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.create_iam_user ? aws_iam_access_key.ecr_k8s_key[0].id : var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.create_iam_user ? aws_iam_access_key.ecr_k8s_key[0].secret : var.aws_secret_access_key
    AWS_REGION            = var.aws_region != null ? var.aws_region : data.aws_region.current.name
    AWS_ACCOUNT_ID        = data.aws_caller_identity.current.account_id
  }

  type = "Opaque"
}

# ServiceAccount for the CronJob
resource "kubernetes_service_account_v1" "ecr_updater" {
  count = var.create_kubernetes_resources ? 1 : 0

  metadata {
    name      = "ecr-credential-updater"
    namespace = kubernetes_namespace_v1.ecr_updater[0].metadata[0].name
  }
}

# ClusterRole to allow creating/updating secrets across namespaces
resource "kubernetes_cluster_role_v1" "ecr_updater" {
  count = var.create_kubernetes_resources ? 1 : 0

  metadata {
    name = "${var.prefix}-ecr-credential-updater"
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

# ClusterRoleBinding
resource "kubernetes_cluster_role_binding_v1" "ecr_updater" {
  count = var.create_kubernetes_resources ? 1 : 0

  metadata {
    name = "${var.prefix}-ecr-credential-updater"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.ecr_updater[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ecr_updater[0].metadata[0].name
    namespace = kubernetes_namespace_v1.ecr_updater[0].metadata[0].name
  }
}


# CronJob to refresh ECR credentials every 6 hours
resource "kubernetes_cron_job_v1" "ecr_credential_refresh" {
  count = var.create_kubernetes_resources ? 1 : 0

  metadata {
    name      = "ecr-credential-refresh"
    namespace = kubernetes_namespace_v1.ecr_updater[0].metadata[0].name
  }

  spec {
    schedule                      = var.cronjob_schedule
    successful_jobs_history_limit = var.successful_jobs_history_limit
    failed_jobs_history_limit     = var.failed_jobs_history_limit

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
            service_account_name = kubernetes_service_account_v1.ecr_updater[0].metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name  = "ecr-credential-updater"
              image = var.cronjob_image

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
                  kubectl create secret docker-registry ${var.secret_name} \
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
                    name = kubernetes_secret_v1.aws_credentials[0].metadata[0].name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.aws_credentials[0].metadata[0].name
                    key  = "AWS_SECRET_ACCESS_KEY"
                  }
                }
              }

              env {
                name = "AWS_REGION"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.aws_credentials[0].metadata[0].name
                    key  = "AWS_REGION"
                  }
                }
              }

              env {
                name = "AWS_ACCOUNT_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.aws_credentials[0].metadata[0].name
                    key  = "AWS_ACCOUNT_ID"
                  }
                }
              }

              resources {
                limits = {
                  cpu    = var.cronjob_cpu_limit
                  memory = var.cronjob_memory_limit
                }
                requests = {
                  cpu    = var.cronjob_cpu_request
                  memory = var.cronjob_memory_request
                }
              }
            }
          }
        }
      }
    }
  }
}