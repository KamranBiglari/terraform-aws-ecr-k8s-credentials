# Simple example with minimal configuration

module "ecr_credentials" {
  source = "../.."

  prefix     = "myapp"
  aws_region = "us-east-1"
}
