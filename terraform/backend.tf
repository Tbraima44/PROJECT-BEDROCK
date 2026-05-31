# Terraform backend configuration
terraform {
  backend "s3" {
    bucket = "project-bedrock-tfstate-alt-soe-025-3778"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}