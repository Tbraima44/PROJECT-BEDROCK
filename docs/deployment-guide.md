# 🚀 Deployment Guide - Project Bedrock

**InnovateMart Retail Store on AWS EKS**

---

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Repository Setup](#repository-setup)
- [Infrastructure Deployment](#infrastructure-deployment)
- [Application Deployment](#application-deployment)
- [CI/CD Pipeline Setup](#cicd-pipeline-setup)
- [Verification Steps](#verification-steps)
- [Developer Access Setup](#developer-access-setup)
- [Troubleshooting](#troubleshooting)
- [Destroy and Rebuild](#destroy-and-rebuild)

---

## Prerequisites

### Local Machine Requirements

| Tool | Version | Installation |
|------|---------|--------------|
| **AWS CLI** | >= 2.0 | `pip install awscli` or [AWS Docs](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| **Terraform** | >= 1.5.0 | `brew install terraform` or [Terraform Downloads](https://developer.hashicorp.com/terraform/downloads) |
| **kubectl** | >= 1.28 | `brew install kubectl` or [Kubernetes Docs](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | >= 3.12 | `brew install helm` or [Helm Docs](https://helm.sh/docs/intro/install/) |
| **jq** | >= 1.6 | `brew install jq` or `apt install jq` |
| **Git** | >= 2.0 | `brew install git` or [Git Downloads](https://git-scm.com/downloads) |

### AWS Requirements

- AWS account with **AdministratorAccess** (or equivalent permissions)
- AWS CLI configured with credentials:
  ```bash
  aws configure
  # Enter Access Key ID, Secret Access Key, region: us-east-1, output: json
  ```

GitHub Requirements

- GitHub account with repository access
- Repository secrets configured (see CI/CD Pipeline Setup)

---

Repository Setup

1. Clone the Repository

```bash
git clone https://github.com/Tbraima44/PROJECT-BEDROCK.git
cd PROJECT-BEDROCK
```

2. Repository Structure

```
├── .github/workflows/          # CI/CD pipelines
│   ├── deploy-app.yaml         # Deploys application to EKS
│   ├── terraform-apply.yml     # Runs on merge to main, applies infrastructure
│   ├── terraform-destroy.yml   # Run manually, delete infrastructure
│   └── terraform-plan.yml      # Runs on PR, posts plan
│
├── docs/                     # Documentation
│   ├── architecture.md
│   ├── architecture.png
│   └── deployment-guide.md
│
├── kubernetes/                 # Application manifests & RBAC
│   ├── helm/
│   │   └── values.yaml                 # Helm values for managed databases
│   ├── observability/
│   │   └── fluentbit.yaml      # FluentBit DaemonSet (optional)
│   ├── rbac/
│   │   ├── aws-load-balancer-controller-clusterrole
│   │   └── dev-view-role.yaml  # RBAC for bedrock-dev-view user access
│   └── retail-store/           # Ingress 
│       └── ingress.yaml
│   
├── lambda/                     # Lambda function source
│   └── bedrock-asset-processor/
│       ├── index.py
│       └── requirements.txt
├── retail-store-app-charts/                  # Helm values for retail store app
│   ├── backend.tf              # S3 remote state
│   ├── dynamodb.tf
│   ├── eks.tf
│   ├── iam.tf
│   ├── lambda.tf
│
├── scripts/                     # Automation scripts
│   ├── deploy-app.sh            # Main application deployment script
│   ├── get-endpoints.sh                # Fetch infrastructure endpoints
│   └── generate-grading-json.sh # Generate grading.json file
│
├── terraform/                  # IaC – VPC, EKS, RDS, IAM, S3, Lambda, etc.
│   ├── backend.tf              # S3 remote state
│   ├── dynamodb.tf
│   ├── eks.tf
│   ├── iam.tf
│   ├── lambda.tf
│   ├── main.tf                 # Provider, secrets, IAM, LB controller
│   ├── outputs.tf
│   ├── rds.tf
│   ├── remote-state.tf         # (not used; bucket created manually)
│   ├── s3.tf
│   ├── variables.tf
│   ├── versions.tf
│   └── vpc.tf
│
├── .gitignore
├── grading.json              # Generated after deployment
└── README.md               
```

3. Configure Variables

Edit terraform/terraform.tfvars:

```hcl
db_username = "admin"
db_password = "YourSecurePassword123!"
student_id  = "YOUR-STUDENT-ID"
```

Or generate with the setup script:

```bash
chmod +x scripts/setup-credentials.sh
./scripts/setup-credentials.sh "YourSecurePassword123!"
```

---

Infrastructure Deployment

Step 1: Create Remote State S3 Bucket

```bash
aws s3api create-bucket \
  --bucket project-bedrock-tfstate-YOUR-STUDENT-ID \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket project-bedrock-tfstate-YOUR-STUDENT-ID \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket project-bedrock-tfstate-YOUR-STUDENT-ID \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Step 2: Initialize Terraform

```bash
cd terraform
terraform init
```

Step 3: Review the Plan

```bash
terraform plan -var="db_password=YourSecurePassword123!"
```

Review the output carefully. You should see:

· VPC with public/private subnets
· EKS cluster with 3 t3.small nodes
· RDS MySQL and PostgreSQL instances
· DynamoDB table
· S3 bucket
· Lambda function
· IAM roles and users

Step 4: Apply Infrastructure

```bash
terraform apply -auto-approve -var="db_password=YourSecurePassword123!"
```

Expected time: 15-25 minutes

Step 5: Verify Infrastructure

```bash
# Check Terraform outputs
terraform output

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name project-bedrock-cluster

# Verify nodes
kubectl get nodes
```

Expected output:

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-10-xxx.ec2.internal   Ready    <none>   5m    v1.34.8-eks-3385e9b
ip-10-0-11-xxx.ec2.internal   Ready    <none>   5m    v1.34.8-eks-3385e9b
ip-10-0-12-xxx.ec2.internal   Ready    <none>   5m    v1.34.8-eks-3385e9b
```

---

Application Deployment

Option 1: Automated Deployment (Recommended)

Run the deployment script:

```bash
cd /path/to/PROJECT-BEDROCK
./scripts/deploy-app.sh
```

This script automatically:

1. Updates kubeconfig
2. Creates the retail-app namespace
3. Applies RBAC configuration
4. Fetches database endpoints from RDS
5. Retrieves credentials from Secrets Manager
6. Installs AWS Load Balancer Controller
7. Deploys all microservices via Helm
8. Applies Ingress for ALB
9. Updates Lambda function
10. Waits for ALB to be provisioned

Option 2: Manual Step-by-Step Deployment

2.1 Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name project-bedrock-cluster
kubectl get nodes
```

2.2 Create Namespace

```bash
kubectl create namespace retail-app
```

2.3 Apply RBAC

```bash
kubectl apply -f kubernetes/rbac/dev-view-role.yaml
kubectl apply -f kubernetes/rbac/aws-load-balancer-controller-clusterrole.yaml
```

2.4 Install AWS Load Balancer Controller

```bash
# Apply CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/config/crd/bases/elbv2.k8s.aws_targetgroupbindings.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/config/crd/bases/elbv2.k8s.aws_ingressclassparams.yaml

# Create TLS certificate
openssl req -x509 -newkey rsa:2048 -keyout tls.key -out tls.crt -days 365 -nodes -subj "/CN=aws-load-balancer-controller"
kubectl create secret tls aws-load-balancer-tls --cert=tls.crt --key=tls.key -n kube-system
rm tls.key tls.crt

# Create ServiceAccount with IRSA
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | \
  kubectl annotate --local -f - "eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/project-bedrock-lb-controller-role" --dry-run=client -o yaml | \
  kubectl apply -f -

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=project-bedrock-vpc" --query 'Vpcs[0].VpcId' --output text)

# Deploy controller
kubectl apply -f kubernetes/aws-load-balancer-controller/install.yaml
# Or use kubectl to create the deployment with --aws-vpc-id=$VPC_ID
```

2.5 Clone Retail Store Sample App

```bash
git clone https://github.com/aws-containers/retail-store-sample-app.git
```

2.6 Deploy Services with Helm

```bash
# Get MySQL endpoint
MYSQL_HOST=$(aws rds describe-db-instances --db-instance-identifier project-bedrock-mysql --query 'DBInstances[0].Endpoint.Address' --output text)

# Carts
helm upgrade --install carts ./retail-store-sample-app/src/cart/chart/ \
  --namespace retail-app \
  --values kubernetes/helm/values.yaml

# Catalog
helm upgrade --install catalog ./retail-store-sample-app/src/catalog/chart/ \
  --namespace retail-app \
  --values kubernetes/helm/values.yaml

# Orders
helm upgrade --install orders ./retail-store-sample-app/src/orders/chart/ \
  --namespace retail-app \
  --values kubernetes/helm/values.yaml

# Checkout
helm upgrade --install checkout ./retail-store-sample-app/src/checkout/chart/ \
  --namespace retail-app \
  --values kubernetes/helm/values.yaml

# UI
helm upgrade --install ui ./retail-store-sample-app/src/ui/chart/ \
  --namespace retail-app
```

2.7 Apply Ingress

```bash
kubectl apply -f kubernetes/retail-store/ingress.yaml
```

2.8 Update Lambda

```bash
cd lambda/bedrock-asset-processor
zip -r ../bedrock-asset-processor.zip index.py
cd ../..
aws lambda update-function-code --function-name bedrock-asset-processor --zip-file fileb://lambda/bedrock-asset-processor.zip --region us-east-1
```

---

CI/CD Pipeline Setup

GitHub Secrets Configuration

Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret.

Add the following secrets:

Secret Name Value Description
AWS_ACCESS_KEY_ID AKIA... IAM user access key
AWS_SECRET_ACCESS_KEY wJalr... IAM user secret key
DB_PASSWORD YourSecurePassword123! Database password

Pipeline Triggers

Workflow File Trigger
Terraform Plan .github/workflows/terraform-plan.yml Pull Request to main (paths: terraform/**)
Terraform Apply .github/workflows/terraform-apply.yml Push to main (paths: terraform/**)
Deploy Application .github/workflows/deploy-app.yaml Push to main (paths: kubernetes/**, lambda/**, scripts/**) or after Terraform Apply completes

Testing the Pipeline

1. Test Terraform Plan:
   ```bash
   git checkout -b test-terraform
   echo "# test" >> terraform/main.tf
   git add terraform/main.tf
   git commit -m "Test terraform plan"
   git push -u origin test-terraform
   ```
   Create a Pull Request on GitHub. The plan output should appear as a comment.
2. Test Terraform Apply:
   Merge the PR to main. The apply workflow should run.
3. Test Deploy Application:
   Push a change to any file in kubernetes/, lambda/, or scripts/. The deployment workflow should run.

---

Verification Steps

1. Check Pod Status

```bash
kubectl get pods -n retail-app
```

Expected output:

```
NAME                       READY   STATUS    RESTARTS   AGE
carts-xxxxxxxx-xxxxx       1/1     Running   0          5m
catalog-xxxxxxxx-xxxxx     1/1     Running   0          5m
checkout-xxxxxxxx-xxxxx    1/1     Running   0          5m
orders-xxxxxxxx-xxxxx      1/1     Running   0          5m
ui-xxxxxxxx-xxxxx          1/1     Running   0          5m
```

2. Get ALB URL

```bash
kubectl get ingress -n retail-app
```

Expected output:

```
NAME                   CLASS    HOSTS   ADDRESS                                                                  PORTS   AGE
retail-store-ingress   <none>   *       k8s-retailap-retailst-xxxxxxxxxx-xxxxxxxxxx.us-east-1.elb.amazonaws.com   80      10m
```

3. Access the Store

Open the ALB URL in your browser:

```
http://k8s-retailap-retailst-xxxxxxxxxx-xxxxxxxxxx.us-east-1.elb.amazonaws.com
```

You should see the InnovateMart Retail Store homepage with product listings.

4. Test Store Functionality

· Browse products
· Add items to cart
· View cart
· Proceed to checkout

5. Verify Logging

```bash
# Control plane logs
aws logs tail /aws/eks/project-bedrock-cluster/cluster --follow

# Application logs
kubectl logs -n retail-app deployment/catalog --tail=20
```

6. Test Serverless Extension

```bash
echo "test image content" > test.jpg
aws s3 cp test.jpg s3://bedrock-assets-YOUR-STUDENT-ID/ --profile bedrock-dev
```

Check CloudWatch Logs:

1. Go to AWS Console → CloudWatch → Log groups
2. Find /aws/lambda/bedrock-asset-processor
3. Look for log entry: "Image received: test.jpg"

7. Test Developer Access

```bash
# Configure developer profile
aws configure --profile bedrock-dev

# Get credentials from Terraform output
cd terraform
terraform output -raw dev_user_access_key
terraform output -raw dev_user_secret_key
cd ..

# Update kubeconfig
aws eks update-kubeconfig --name project-bedrock-cluster --profile bedrock-dev --region us-east-1

# Test read access (should succeed)
kubectl get pods -n retail-app

# Test delete (should fail with Forbidden)
kubectl delete pod -n retail-app <any-pod>
```

---

Developer Access Setup

IAM User: bedrock-dev-view

This user has:

· AWS Console: ReadOnlyAccess managed policy
· S3: s3:PutObject on bedrock-assets-* bucket
· Kubernetes: view ClusterRole (read-only)

Credentials

Get credentials from Terraform output:

```bash
cd terraform
echo "Access Key: $(terraform output -raw dev_user_access_key)"
echo "Secret Key: $(terraform output -raw dev_user_secret_key)"
cd ..
```

Kubernetes Access

The user is mapped to the view ClusterRole via the aws-auth ConfigMap. This is configured automatically by the deployment script.

---

Troubleshooting

Issue: Terraform Apply Hangs on EKS

Solution: Wait. EKS cluster creation takes 15-25 minutes.

Issue: Pods in CrashLoopBackOff

Solution: Check logs:

```bash
kubectl logs -n retail-app deployment/<service> --tail=50
```

Common causes:

· Wrong database credentials: Verify Secrets Manager value
· Missing MySQL driver: Use Helm chart instead of raw manifest
· Database not reachable: Check security group rules

Issue: ALB Not Provisioning

Solution: Check LB controller logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50
```

Common causes:

· Missing CRDs: Apply CRDs manually
· RBAC permissions: Update ClusterRole
· IAM policy: Check inline policy includes all required actions

Issue: "Too Many Pods" Error

Solution: Increase node count in terraform/eks.tf:

```hcl
scaling_config {
  desired_size = 3
  max_size     = 4
  min_size     = 2
}
```

Issue: Terraform Destroy Fails

Solution: Manually clean up dependencies:

```bash
# Delete ALB
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-retailap`)].LoadBalancerArn' --output text | xargs -n1 aws elbv2 delete-load-balancer --load-balancer-arn

# Release EIPs
aws ec2 describe-addresses --region us-east-1 --query 'Addresses[*].AllocationId' --output text | xargs -n1 aws ec2 release-address --allocation-id

# Delete NAT Gateways
aws ec2 describe-nat-gateways --region us-east-1 --filter "Name=tag:Project,Values=karatu-2025-capstone" --query 'NatGateways[*].NatGatewayId' --output text | xargs -n1 aws ec2 delete-nat-gateway --nat-gateway-id

# Wait 2-3 minutes, then retry
terraform destroy -auto-approve -var="db_password=YourSecurePassword123!"
```

Issue: Secrets Manager "Scheduled for Deletion" Error

Solution:

```bash
aws secretsmanager delete-secret \
  --secret-id project-bedrock-db-credentials \
  --force-delete-without-recovery \
  --region us-east-1
```

---

Destroy and Rebuild

Full Cleanup

```bash
# 1. Delete application
helm uninstall carts catalog orders checkout ui -n retail-app
kubectl delete namespace retail-app

# 2. Destroy infrastructure
cd terraform
terraform destroy -auto-approve -var="db_password=YourSecurePassword123!"
cd ..

# 3. Clean up orphaned resources (if any)
# See troubleshooting section above

# 4. Refresh state
cd terraform
terraform refresh -var="db_password=YourSecurePassword123!"
cd ..
```

Full Rebuild

```bash
# 1. Apply infrastructure
cd terraform
terraform apply -auto-approve -var="db_password=YourSecurePassword123!"
cd ..

# 2. Deploy application
./scripts/deploy-app.sh

# 3. Verify
kubectl get pods -n retail-app
kubectl get ingress -n retail-app
```

---

Environment Variables Reference

Variable Value Description
AWS_REGION us-east-1 AWS region
CLUSTER_NAME project-bedrock-cluster EKS cluster name
NAMESPACE retail-app Kubernetes namespace
DB_USERNAME admin MySQL username
DB_PASSWORD YourSecurePassword123! MySQL password
DYNAMODB_TABLE project-bedrock-retail-store DynamoDB table name

---

Useful Commands

Kubernetes

```bash
# Get all resources in namespace
kubectl get all -n retail-app

# Watch pods
kubectl get pods -n retail-app -w

# Describe a pod
kubectl describe pod -n retail-app <pod-name>

# Get logs
kubectl logs -n retail-app deployment/<service> --tail=100 -f

# Exec into a pod
kubectl exec -it -n retail-app <pod-name> -- /bin/bash
```

Helm

```bash
# List releases
helm list -n retail-app

# Get values
helm get values carts -n retail-app

# Rollback
helm rollback carts -n retail-app

# Uninstall
helm uninstall carts -n retail-app
```

Terraform

```bash
# Validate configuration
terraform validate

# Format code
terraform fmt -recursive

# Show state
terraform state list

# Show resource details
terraform state show <resource>

# Taint a resource (force recreate)
terraform taint <resource>
```

AWS CLI

```bash
# Get RDS endpoints
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address]' --output table

# Get EKS cluster info
aws eks describe-cluster --name project-bedrock-cluster

# Get Secrets Manager value
aws secretsmanager get-secret-value --secret-id project-bedrock-db-credentials --query SecretString --output text | jq
```

---

Support

For issues or questions:

· Check the Troubleshooting section
· Review the AWS EKS Documentation
· Review the Terraform AWS Provider Documentation

```

---

