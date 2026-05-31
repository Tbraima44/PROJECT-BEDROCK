#!/bin/bash
# Script to help you set up credentials and get endpoints
set -e

echo "=== Project Bedrock Credentials Setup ==="
echo ""

# Check if password is provided as argument
if [ -z "$1" ]; then
  echo "⚠️  Please provide a database password as argument"
  echo "Usage: ./scripts/setup-credentials.sh <your-db-password>"
  echo ""
  
  # Generate a random password
  DB_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
  echo "💡 Generated random password: $DB_PASSWORD"
  echo "   You can use this or provide your own"
  exit 1
else
  DB_PASSWORD="$1"
fi

# Export for Terraform
export TF_VAR_db_password="$DB_PASSWORD"

echo "✅ Database password set: $DB_PASSWORD"
echo ""

# Create terraform.tfvars if it doesn't exist
if [ ! -f "terraform/terraform.tfvars" ]; then
  echo "📝 Creating terraform.tfvars..."
  cat > terraform/terraform.tfvars <<EOF
db_username = "admin"
db_password = "$DB_PASSWORD"
student_id  = "YOUR-STUDENT-ID"  # REPLACE THIS!
EOF
  echo "⚠️  IMPORTANT: Edit terraform/terraform.tfvars and replace YOUR-STUDENT-ID"
else
  echo "📝 terraform.tfvars already exists"
  # Update password in existing tfvars
  if grep -q "db_password" terraform/terraform.tfvars; then
    sed -i "s/db_password.*/db_password = \"$DB_PASSWORD\"/" terraform/terraform.tfvars
    echo "✅ Updated password in terraform.tfvars"
  else
    echo "db_password = \"$DB_PASSWORD\"" >> terraform/terraform.tfvars
  fi
fi

echo ""
echo "📋 Next steps:"
echo "1. Edit terraform/terraform.tfvars with your student ID"
echo "2. Run: cd terraform && terraform init"
echo "3. Run: terraform plan"
echo "4. Run: terraform apply"
echo ""
echo "After apply, run: ./scripts/get-endpoints.sh"