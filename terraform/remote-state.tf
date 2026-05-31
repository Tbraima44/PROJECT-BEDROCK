# Remote state configuration
# S3 bucket for remote state storage
# resource "aws_s3_bucket" "terraform_state" {
#   bucket = "project-bedrock-tfstate-${var.student_id}"
  
#   tags = {
#     Name    = "Terraform State Bucket"
#     Project = "karatu-2025-capstone"
#   }
# }

# resource "aws_s3_bucket_versioning" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#   versioning_configuration {
#     status = "Enabled"
#   }
# }

# resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "AES256"
#     }
#   }
# }

# Remote state configuration (to be used in backend block)
# Note: The actual backend config will be in a backend.tf file or via CLI