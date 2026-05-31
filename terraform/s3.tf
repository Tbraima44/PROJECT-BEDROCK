# S3 buckets configuration
# S3 Bucket for Assets
resource "aws_s3_bucket" "assets" {
  bucket = "bedrock-assets-${var.student_id}"
  
  tags = {
    Name    = "bedrock-assets-${var.student_id}"
    Project = "karatu-2025-capstone"
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}