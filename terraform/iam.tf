# IAM roles, users, and policies
# Developer IAM User
resource "aws_iam_user" "bedrock_dev_view" {
  name = "bedrock-dev-view"
  
  tags = {
    Project = "karatu-2025-capstone"
  }
}

# Attach ReadOnlyAccess policy
resource "aws_iam_user_policy_attachment" "read_only_access" {
  user       = aws_iam_user.bedrock_dev_view.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Custom policy for S3 PutObject on assets bucket
resource "aws_iam_policy" "s3_put_object" {
  name        = "bedrock-assets-put-object"
  description = "Allow PutObject on assets bucket"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${aws_s3_bucket.assets.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "s3_put_object" {
  user       = aws_iam_user.bedrock_dev_view.name
  policy_arn = aws_iam_policy.s3_put_object.arn
}

# Generate access keys for the user
resource "aws_iam_access_key" "bedrock_dev_view" {
  user = aws_iam_user.bedrock_dev_view.name
}