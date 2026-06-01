FROM alpine/k8s:1.33.12

# Install AWS CLI and other dependencies
RUN apk add --no-cache \
    aws-cli \
    bash \
    curl \
    jq

# Verify the required commands are available after installation
RUN for cmd in aws kubectl base64 bash curl jq; do \
        if ! command -v "$cmd" >/dev/null 2>&1; then \
            echo "ERROR: required command '$cmd' is not available" >&2; \
            exit 1; \
        fi; \
        echo "Found required command: $cmd"; \
    done

# Set working directory
WORKDIR /app

# Use bash as the default shell for better script compatibility
SHELL ["/bin/bash", "-c"]

# Add a non-root user for security
RUN adduser -D -u 1000 kubectl-user

# Switch to non-root user
USER kubectl-user

# Default command
CMD ["/bin/bash"]
