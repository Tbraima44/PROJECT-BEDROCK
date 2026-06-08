#!/bin/bash
# Generate grading.json from Terraform outputs

echo "📊 Generating grading.json..."

# Navigate to terraform directory
cd "$(dirname "$0")/../terraform"

# Generate the JSON
terraform output -json > ../grading.json

echo "✅ grading.json generated successfully!"
echo "File location: $(dirname "$0")/../grading.json"
