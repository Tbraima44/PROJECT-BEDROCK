# Project Bedrock - InnovateMart EKS Deployment

## Overview
Production-grade microservices deployment on AWS EKS for InnovateMart's retail store application.

## Architecture
- EKS Cluster with managed node groups
- RDS MySQL and PostgreSQL databases
- DynamoDB tables
- S3 bucket with Lambda processing
- CloudWatch logging and monitoring
- CI/CD with GitHub Actions

## Prerequisites
- AWS Account with appropriate permissions
- Terraform >= 1.5.0
- kubectl
- AWS CLI
- Docker (for Lambda packaging)

## Quick Start
1. Clone the repository
2. Configure AWS credentials
3. Run the setup script
4. Follow the deployment guide in docs/

## Directory Structure

project-bedrock/
├── terraform/           # Infrastructure as Code
├── kubernetes/          # Kubernetes manifests
├── lambda/              # Serverless functions
├── .github/            # CI/CD workflows
├── docs/               # Documentation
├── grading.json
├── README.md
├── scripts/            # Utility scripts
└── environments/       # Environment-specific configs



## 📋 Quick Start Guide

### 1. Set Up Credentials
```bash
# Generate and set database password
chmod +x scripts/setup-credentials.sh
./scripts/setup-credentials.sh "YourSecurePassword123!"
```
# Edit terraform/terraform.tfvars
# Replace YOUR-STUDENT-ID with your actual student ID

2. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

3. Get Endpoints

```bash
cd ..
./scripts/get-endpoints.sh
```

4. Deploy Application

```bash
./scripts/deploy-app.sh
```

5. Access the Application

After deployment, get your ALB URL:

```bash
kubectl get ingress retail-store-ingress -n retail-app
```

The URL will be in the ADDRESS column. Update this README with that URL.

🔧 Infrastructure Details

Database Connections

· MySQL: project-bedrock-mysql.xxxxx.us-east-1.rds.amazonaws.com:3306
· PostgreSQL: project-bedrock-postgresql.xxxxx.us-east-1.rds.amazonaws.com:5432
· DynamoDB: project-bedrock-retail-store

Developer Access

· IAM User: bedrock-dev-view
· AWS Console: ReadOnlyAccess + S3 PutObject on assets bucket
· Kubernetes: View-only ClusterRole in retail-app namespace

📊 Monitoring

· CloudWatch Logs: /aws/eks/project-bedrock-cluster/cluster
· Container Insights: /aws/containerinsights/project-bedrock-cluster/application

🧹 Cleanup

```bash
# Delete application
kubectl delete namespace retail-app

# Destroy infrastructure
cd terraform
terraform destroy -auto-approve
```

```



# STEP 9: Generate grading.json
cd terraform
terraform output -json > grading.json

# STEP 10: Commit everything
cd ..
git add .
git commit -m "Complete Project Bedrock deployment"
git push
```

This approach ensures:

1. No conflicts between main.tf, vpc.tf, and eks.tf
2. Clear process for getting database passwords and endpoints
3. Simple merge of the cloned retail store app with your custom configurations
4. Clear location for the ALB URL in your documentation

The deployment scripts handle the merge process automatically by:

· Cloning the retail store app
· Deploying only the application services
· Removing in-cluster databases
· Applying patches for managed AWS databases
· Configuring all endpoints dynamically