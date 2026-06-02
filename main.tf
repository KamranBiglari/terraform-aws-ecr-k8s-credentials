# IAM user for ECR access (for pulling images from K8s)
resource "aws_iam_user" "ecr_k8s_user" {
  count = var.create_iam_user ? 1 : 0

  name = coalesce(
    var.iam_user_name,
    "${var.prefix}-ecr-k8s-user"
  )
  path = var.iam_user_path

  tags = merge(
    {
      Name = coalesce(
        var.iam_user_name,
        "${var.prefix}-ecr-k8s-user"
      )
    },
    var.tags
  )
}

# IAM policy for ECR read access
resource "aws_iam_user_policy" "ecr_k8s_policy" {
  count = var.create_iam_user ? 1 : 0

  name = coalesce(
    var.iam_user_policy_name,
    "${var.prefix}-ecr-k8s-policy"
  )
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
  user  = aws_iam_user.ecr_k8s_user[0].name
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
    name      = "${var.prefix}-aws-credentials"
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
    name      = "${var.prefix}-ecr-credential-updater"
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
    name      = "${var.prefix}-ecr-credential-refresh"
    namespace = kubernetes_namespace_v1.ecr_updater[0].metadata[0].name
  }

  spec {
    schedule                      = var.cronjob_schedule
    successful_jobs_history_limit = var.successful_jobs_history_limit
    failed_jobs_history_limit     = var.failed_jobs_history_limit
    concurrency_policy            = var.cronjob_concurrency_policy
    starting_deadline_seconds     = var.cronjob_starting_deadline_seconds

    job_template {
      metadata {
        name = "${var.prefix}-ecr-credential-refresh"
      }

      spec {
        template {
          metadata {
            labels = {
              app = "${var.prefix}-ecr-credential-refresh"
            }
          }

          spec {
            service_account_name = kubernetes_service_account_v1.ecr_updater[0].metadata[0].name
            restart_policy       = "OnFailure"

            node_selector = var.cronjob_node_selector
            dynamic "toleration" {
              for_each = var.cronjob_tolerations
              content {
                key                = toleration.value.key
                operator           = toleration.value.operator
                value              = toleration.value.value
                effect             = toleration.value.effect
                toleration_seconds = toleration.value.toleration_seconds
              }
            }

            security_context {
              run_as_non_root = true
              run_as_user     = 1000
              fs_group        = 1000
              seccomp_profile {
                type = "RuntimeDefault"
              }
            }

            # Writable scratch dirs so the container can keep a read-only root
            # filesystem while still letting kubectl/aws write their caches.
            volume {
              name = "tmp"
              empty_dir {}
            }

            volume {
              name = "home"
              empty_dir {}
            }

            container {
              name              = "${var.prefix}-ecr-credential-updater"
              image             = var.cronjob_image
              image_pull_policy = var.cronjob_image_pull_policy

              command = ["/bin/bash", "-c"]
              args    = [local.refresh_script]

              security_context {
                allow_privilege_escalation = false
                read_only_root_filesystem  = true
                run_as_non_root            = true
                run_as_user                = 1000
                capabilities {
                  drop = ["ALL"]
                }
              }

              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
              }

              volume_mount {
                name       = "home"
                mount_path = "/home/kubectl-user"
              }

              dynamic "env" {
                for_each = local.ecr_updater_secret_env
                content {
                  name = env.value
                  value_from {
                    secret_key_ref {
                      name = kubernetes_secret_v1.aws_credentials[0].metadata[0].name
                      key  = env.value
                    }
                  }
                }
              }

              env {
                name  = "TARGET_NAMESPACES"
                value = var.target_namespaces
              }

              env {
                name  = "EXCLUDE_NAMESPACES"
                value = var.exclude_namespaces
              }

              env {
                name  = "HOME"
                value = "/home/kubectl-user"
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

# One-shot Job to populate the credentials immediately on apply, so workloads
# don't have to wait for the first scheduled CronJob run (up to a full interval).
resource "kubernetes_job_v1" "ecr_credential_bootstrap" {
  count = var.create_kubernetes_resources && var.create_bootstrap_job ? 1 : 0

  metadata {
    name      = "${var.prefix}-ecr-credential-bootstrap"
    namespace = kubernetes_namespace_v1.ecr_updater[0].metadata[0].name
  }

  spec {
    backoff_limit              = 2
    ttl_seconds_after_finished = var.bootstrap_job_ttl_seconds

    template {
      metadata {
        labels = {
          app = "${var.prefix}-ecr-credential-refresh"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.ecr_updater[0].metadata[0].name
        restart_policy       = "OnFailure"

        node_selector = var.cronjob_node_selector
        dynamic "toleration" {
          for_each = var.cronjob_tolerations
          content {
            key                = toleration.value.key
            operator           = toleration.value.operator
            value              = toleration.value.value
            effect             = toleration.value.effect
            toleration_seconds = toleration.value.toleration_seconds
          }
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }

        volume {
          name = "home"
          empty_dir {}
        }

        container {
          name              = "${var.prefix}-ecr-credential-updater"
          image             = var.cronjob_image
          image_pull_policy = var.cronjob_image_pull_policy

          command = ["/bin/bash", "-c"]
          args    = [local.refresh_script]

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 1000
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/kubectl-user"
          }

          dynamic "env" {
            for_each = local.ecr_updater_secret_env
            content {
              name = env.value
              value_from {
                secret_key_ref {
                  name = kubernetes_secret_v1.aws_credentials[0].metadata[0].name
                  key  = env.value
                }
              }
            }
          }

          env {
            name  = "TARGET_NAMESPACES"
            value = var.target_namespaces
          }

          env {
            name  = "EXCLUDE_NAMESPACES"
            value = var.exclude_namespaces
          }

          env {
            name  = "HOME"
            value = "/home/kubectl-user"
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

  # Jobs are immutable; let Terraform replace it when the script/config changes.
  wait_for_completion = var.bootstrap_job_wait_for_completion
}