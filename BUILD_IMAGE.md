# Building and Using Custom Docker Image

This module includes a Dockerfile that pre-installs all necessary dependencies (AWS CLI, kubectl, etc.) to avoid installing them during every cronjob execution, making the credential refresh much faster.

## Building the Image

### Build locally

```bash
docker build -t <your-dockerhub-username>/ecr-k8s-updater:latest .
```

### Build for multiple platforms

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t <your-dockerhub-username>/ecr-k8s-updater:latest .
```

## Pushing to Docker Hub

1. Login to Docker Hub:
```bash
docker login
```

2. Push the image:
```bash
docker push <your-dockerhub-username>/ecr-k8s-updater:latest
```

3. Tag with version (optional):
```bash
docker tag <your-dockerhub-username>/ecr-k8s-updater:latest <your-dockerhub-username>/ecr-k8s-updater:v1.0.0
docker push <your-dockerhub-username>/ecr-k8s-updater:v1.0.0
```

## Using the Custom Image

In your Terraform configuration, specify your custom image:

```hcl
module "ecr_credentials" {
  source = "path/to/terraform-aws-ecr-k8s-credentials"

  prefix        = "my-app"
  cronjob_image = "<your-dockerhub-username>/ecr-k8s-updater:latest"

  # Other variables...
}
```

## Default Image

By default, the module uses the prebuilt `kamranbiglari/ecr-k8s-updater` image (kubectl + AWS CLI baked in), so nothing is installed at runtime.

The [Tag and Release workflow](.github/workflows/tag.yaml) builds and pushes this image on every merge to `main`: it bumps the version, pushes both `:latest` and `:vX.Y.Z`, and then **pins the module's `cronjob_image` default to that exact version** (committing the change back to `variables.tf`). This means consumers get an immutable, reproducible tag by default rather than a moving `:latest`. Set `cronjob_image_pull_policy = "Always"` only if you intentionally track `:latest`.

## Benefits of Custom Image

- **Faster execution**: No need to install AWS CLI on every run
- **Reduced network overhead**: Dependencies are pre-installed
- **More reliable**: Avoids potential package repository issues during runtime
- **Consistent environment**: Same dependencies across all executions

## Image Contents

The custom image includes:
- `alpine/k8s:1.30.7` base (includes kubectl)
- AWS CLI
- bash
- curl
- jq
- Non-root user for security
