locals {
  # Names of the secret keys (in kubernetes_secret_v1.aws_credentials) that are
  # injected into the updater containers as environment variables. Kept as a
  # list so the CronJob and the bootstrap Job can share a single dynamic block.
  ecr_updater_secret_env = [
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_REGION",
    "AWS_ACCOUNT_ID",
  ]

  # The credential-refresh script, shared between the scheduled CronJob and the
  # one-shot bootstrap Job so both always run identical logic.
  # Raw heredoc; CRs are stripped below so a CRLF checkout of this file (common
  # on Windows with core.autocrlf=true) cannot leak "\r" into the container shell.
  refresh_script_raw = <<-EOT
    #!/bin/bash
    set -e

    echo "Checking required commands are available..."
    MISSING_COMMANDS=""
    for cmd in aws kubectl; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_COMMANDS="$MISSING_COMMANDS $cmd"
      fi
    done

    if [ -n "$MISSING_COMMANDS" ]; then
      echo "ERROR: The following required commands are not available:$MISSING_COMMANDS" >&2
      exit 1
    fi

    echo "Fetching ECR authorization token..."
    TOKEN=$(aws ecr get-login-password --region $AWS_REGION)

    # Get namespaces from env variable or discover all via kubectl
    if [ -n "$TARGET_NAMESPACES" ]; then
      echo "Using namespaces from TARGET_NAMESPACES variable..."
      NAMESPACES="$TARGET_NAMESPACES"
    else
      echo "Discovering all namespaces via kubectl..."
      NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
    fi

    echo "Found namespaces: $NAMESPACES"

    for NAMESPACE in $NAMESPACES; do
      # Skip namespaces explicitly excluded via EXCLUDE_NAMESPACES
      case " $EXCLUDE_NAMESPACES " in
        *" $NAMESPACE "*)
          echo "Skipping excluded namespace: $NAMESPACE"
          continue
          ;;
      esac

      echo "Updating secret in namespace: $NAMESPACE"

      # Create or update the secret, continue on error
      if kubectl create secret docker-registry ${var.secret_name} \
        --docker-server=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com \
        --docker-username=AWS \
        --docker-password=$TOKEN \
        --namespace=$NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -; then
        echo "Secret updated successfully in $NAMESPACE"
      else
        echo "WARNING: Failed to update secret in $NAMESPACE (namespace may not exist), continuing..."
      fi
    done

    echo "ECR credentials refresh completed successfully!"
  EOT

  refresh_script = replace(local.refresh_script_raw, "\r", "")
}
