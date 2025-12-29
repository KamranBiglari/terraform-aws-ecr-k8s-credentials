FROM alpine/k8s:1.30.7

# Install AWS CLI and other dependencies
RUN apk add --no-cache \
    aws-cli \
    bash \
    curl \
    jq

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
