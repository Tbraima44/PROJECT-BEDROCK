# DynamoDB tables configuration
# DynamoDB Table for the retail store app
resource "aws_dynamodb_table" "retail_store" {
  name           = "project-bedrock-retail-store"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  
  attribute {
    name = "id"
    type = "S"
  }
  
  tags = {
    Project = "karatu-2025-capstone"
  }
}