#!/bin/bash
# Script to get all endpoints after Terraform apply
set -e

echo "=== Project Bedrock Endpoints ==="
echo ""

# Get Terraform outputs
cd terraform

echo "🔍 Retrieving infrastructure information..."
echo ""

# Cluster info
CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)
CLUSTER_NAME=$(terraform output -raw cluster_name)
echo "EKS Cluster:"
echo "  Name: $CLUSTER_NAME"
echo "  Endpoint: $CLUSTER_ENDPOINT"
echo ""

# Database endpoints
echo "Databases:"
MYSQL_ENDPOINT=$(terraform output -raw mysql_endpoint)
echo "  MySQL: $MYSQL_ENDPOINT"

POSTGRES_ENDPOINT=$(terraform output -raw postgresql_endpoint)
echo "  PostgreSQL: $POSTGRES_ENDPOINT"

DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name)
echo "  DynamoDB: $DYNAMODB_TABLE"
echo ""

# VPC
VPC_ID=$(terraform output -raw vpc_id)
echo "VPC: $VPC_ID"
echo ""

# S3
BUCKET_NAME=$(terraform output -raw assets_bucket_name)
echo "S3 Assets Bucket: $BUCKET_NAME"
echo ""

# Export endpoints to a file for Kubernetes manifests
echo "📝 Creating endpoints file for Kubernetes..."
cat > ../kubernetes/retail-store/endpoints.env <<EOF
MYSQL_HOST=$MYSQL_ENDPOINT
MYSQL_PORT=3306
POSTGRES_HOST=$POSTGRES_ENDPOINT
POSTGRES_PORT=5432
DYNAMODB_TABLE=$DYNAMODB_TABLE
EOF

echo "✅ Endpoints saved to kubernetes/retail-store/endpoints.env"
echo ""

# Update kubeconfig
echo "🔧 Updating kubeconfig..."
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME
echo "✅ Kubeconfig updated"
echo ""

# Get credentials from Secrets Manager
echo "🔑 Retrieving database credentials..."
aws secretsmanager get-secret-value \
  --secret-id project-bedrock-db-credentials \
  --query 'SecretString' \
  --output text | jq '.'

echo ""
echo "📋 Next step: Run ./scripts/deploy-app.sh to deploy the application"