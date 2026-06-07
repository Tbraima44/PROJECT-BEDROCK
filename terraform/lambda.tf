# Lambda function configuration
# Lambda IAM Role
resource "aws_iam_role" "lambda" {
  name = "bedrock-asset-processor-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Project = "karatu-2025-capstone"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda.name
}

# Lambda Function
resource "aws_lambda_function" "asset_processor" {
  filename         = "../lambda/bedrock-asset-processor.zip"
  function_name    = "bedrock-asset-processor"
  role            = aws_iam_role.lambda.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  # source_code_hash = filebase64sha256("../lambda/bedrock-asset-processor.zip")
  
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.assets.id
    }
  }
  
  tags = {
    Project = "karatu-2025-capstone"
  }
}

# S3 Bucket Notification
resource "aws_s3_bucket_notification" "assets_notification" {
  bucket = aws_s3_bucket.assets.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.asset_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_function.asset_processor,
    aws_lambda_permission.allow_s3
  ]
}
# Lambda Permission for S3
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asset_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.assets.arn
}