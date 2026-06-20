# 🚀 Deployment Guide - Project Bedrock

**InnovateMart Retail Store on AWS EKS**

---

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Architecture Overview](#architecture-overview)
- [Repository Setup](#repository-setup)
- [Infrastructure Deployment](#infrastructure-deployment)
- [Application Deployment](#application-deployment)
  - [Option 1: Automated Deployment (Recommended)](#option-1-automated-deployment-recommended)
  - [Option 2: Manual Step-by-Step Deployment](#option-2-manual-step-by-step-deployment)
- [CI/CD Pipeline Setup](#cicd-pipeline-setup)
- [Verification Steps](#verification-steps)
- [Developer Access Setup](#developer-access-setup)
- [Observability](#observability)
- [Troubleshooting](#troubleshooting)
- [Destroy and Rebuild](#destroy-and-rebuild)
- [Useful Commands](#useful-commands)

---

## Prerequisites

### Local Machine Requirements

| **Tool** | **Version** | **Installation** |
|--------------|--------------|--------------|
| **AWS CLI** | >= 2.0 | `pip install awscli` (v2) or official installer |
| **Terraform** | >= 1.5.0 | `brew install terraform` or HashiCorp repo for Linux |
| **kubectl** | >= 1.28 | `brew install kubectl` or official guide for Linux |
| **Helm** | >= 3.12 | `brew install helm` or `snap install helm` |
| **jq** | >= 1.6 | `brew install jq` or `apt install jq` |
| **Git** | >= 2.0 | `brew install git` or `apt install git` |

### AWS Requirements

- AWS account with **AdministratorAccess** (or equivalent permissions)
- AWS CLI configured with credentials:
  ```bash
  aws configure
  # Enter Access Key ID, Secret Access Key, region: us-east-1, output: json
  ```

###   GitHub Requirements

- GitHub account with repository access
- Repository secrets configured (see CI/CD Pipeline Setup)

---

## Architecture Overview

![alt text](architecture.png)

---

##   Repository Setup

### 1. Clone the Repository

```bash
git clone https://github.com/Tbraima44/PROJECT-BEDROCK.git
cd PROJECT-BEDROCK
```

### 2. Repository Structure

```
├── .github/workflows/          # CI/CD pipelines
│   ├── deploy-app.yaml         # Deploys application to EKS
│   ├── terraform-apply.yml     # Runs on merge to main, applies infrastructure
│   └── terraform-plan.yml      # Runs on PR, posts plan
│
├── docs/                     # Documentation
│   ├── architecture.md
│   ├── architecture.png
│   └── deployment-guide.md
│
├── kubernetes/                 # Application manifests & RBAC
│   ├── aws-load-balancer-controller/
│   │   └── deployment.yaml
│   ├── helm/
│   │   └── values.yaml                 # Helm values for managed databases overrides
│   ├── rbac/
│   │   ├── aws-load-balancer-controller-clusterrole
│   │   └── dev-view-role.yaml  # RBAC for bedrock-dev-view user access
│   └── retail-store/           # Ingress
│       ├── rabbitmq.yaml
│       ├── redis.yaml
│       └── ingress.yaml
│   
├── lambda/                     # Lambda function source
│   └── bedrock-asset-processor/
│       ├── index.py
│       └── requirements.txt
│
├── retail-store-app-charts/    # Helm charts for the Retail Store App 
│   ├── cart/chart/              
│   ├── catalog/chart/
│   ├── checkout/chart/
│   ├── orders/chart/
│   ├── ui/chart/
│
├── scripts/                     # Automation scripts
│   ├── deploy-app.sh            # Main application deployment script
│   ├── destroy-all.sh           #  Destroy all resources
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

### 3. Configure Variables

Edit terraform/terraform.tfvars:

```hcl
db_username = "admin"
db_password = "YourSecurePassword123!"
student_id  = "YOUR-STUDENT-ID"
```

---

## Infrastructure Deployment

### Step 1: Create Remote State S3 Bucket

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

### Step 2: Initialize Terraform

```bash
cd terraform
terraform init
```

### Step 3: Review the Plan

```bash
terraform plan -var="db_password=YourSecurePassword123!"
```

**Review** the output carefully. You should see:

- VPC with public/private subnets
- EKS cluster with 3 t3.small nodes
- RDS MySQL and PostgreSQL instances
- DynamoDB table
- S3 bucket
- Lambda function
- IAM roles and users

### Step 4: Apply Infrastructure

```bash
terraform apply -auto-approve -var="db_password=YourSecurePassword123!"
```

**Expected time:** 15-25 minutes

### Step 5: Verify Infrastructure

```bash
# Check Terraform outputs
terraform output
```

---

##  Application Deployment

### Option 1: Automated Deployment (Recommended)

**Run the deployment script:**

```bash
cd /path/to/PROJECT-BEDROCK
./scripts/deploy-app.sh
```

**This script automatically:**

1. Updates kubeconfig
2. Creates the retail-app namespace
3. Applies RBAC configuration
4. Fetches database endpoints from RDS
5. Retrieves credentials from Secrets Manager
6. Installs AWS Load Balancer Controller
7. Deploys microservices via Helm and Kubernetes manifest 
8. Applies Ingress for ALB
9. Updates Lambda function
10. Waits for ALB to be provisioned

###  Verify Deployment

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name project-bedrock-cluster

# Verify nodes
kubectl get nodes
```

**Expected output:**

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-10-xxx.ec2.internal   Ready    <none>   5m    v1.34.8-eks-3385e9b
ip-10-0-11-xxx.ec2.internal   Ready    <none>   5m    v1.34.8-eks-3385e9b
ip-10-0-12-xxx.ec2.internal   Ready    <none>   5m    v1.34.8-eks-3385e9b
```

### Option 2: Manual Step-by-Step Deployment

**Step 1: Connect to EKS**

```bash
aws eks update-kubeconfig --region us-east-1 --name project-bedrock-cluster
kubectl get nodes
```

**Step 2: Create Namespace**

```bash
kubectl create namespace retail-app
```

**Step 3: Install AWS Load Balancer Controller**

```bash
# Apply CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/config/crd/bases/elbv2.k8s.aws_targetgroupbindings.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/config/crd/bases/elbv2.k8s.aws_ingressclassparams.yaml

# Apply RBAC
kubectl apply -f kubernetes/rbac/aws-load-balancer-controller-clusterrole.yaml

# Generate TLS certificate
openssl req -x509 -newkey rsa:2048 -keyout tls.key -out tls.crt -days 365 -nodes -subj "/CN=aws-load-balancer-controller"
kubectl create secret tls aws-load-balancer-tls --cert=tls.crt --key=tls.key -n kube-system
rm tls.key tls.crt

# Create ServiceAccount with IRSA
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | \
  kubectl annotate --local -f - "eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/project-bedrock-lb-controller-role" --dry-run=client -o yaml | \
  kubectl apply -f -

# Apply ClusterRoleBinding
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: aws-load-balancer-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: aws-load-balancer-controller
subjects:
- kind: ServiceAccount
  name: aws-load-balancer-controller
  namespace: kube-system
EOF

# Get VPC ID and deploy controller
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=project-bedrock-vpc" --query 'Vpcs[0].VpcId' --output text)
sed "s/--aws-vpc-id=.*/--aws-vpc-id=$VPC_ID/" kubernetes/aws-load-balancer-controller/deployment.yaml | kubectl apply -f -

# Wait for controller
kubectl wait --for=condition=available --timeout=120s deployment/aws-load-balancer-controller -n kube-system
```

**Step 4: Deploy Retail Store with Helm**

```bash
# Deploy each service using local charts
helm upgrade --install carts ./retail-store-app-charts/cart/chart/ \
  --namespace retail-app --values kubernetes/helm/values.yaml

helm upgrade --install catalog ./retail-store-app-charts/catalog/chart/ \
  --namespace retail-app --values kubernetes/helm/values.yaml

helm upgrade --install orders ./retail-store-app-charts/orders/chart/ \
  --namespace retail-app --values kubernetes/helm/values.yaml

helm upgrade --install checkout ./retail-store-app-charts/checkout/chart/ \
  --namespace retail-app --values kubernetes/helm/values.yaml

helm upgrade --install ui ./retail-store-app-charts/ui/chart/ \
  --namespace retail-app
```

**Step 5: Deploy RabbitMQ and Redis**

```bash
kubectl apply -f kubernetes/retail-store/rabbitmq.yaml
kubectl apply -f kubernetes/retail-store/redis.yaml
```

**Step 6: Enable CloudWatch Observability**

```bash
aws eks create-addon \
  --cluster-name project-bedrock-cluster \
  --addon-name amazon-cloudwatch-observability \
  --region us-east-1
```

**Step 7: Apply RBAC and Ingress**

```bash
kubectl apply -f kubernetes/rbac/dev-view-role.yaml
kubectl apply -f kubernetes/retail-store/ingress.yaml
```

**Step 8: Update Lambda Function**

```bash
cd lambda/bedrock-asset-processor
zip -r ../bedrock-asset-processor.zip index.py
cd ../..
aws lambda update-function-code \
  --function-name bedrock-asset-processor \
  --zip-file fileb://lambda/bedrock-asset-processor.zip \
  --region us-east-1
```

**Step 9: Get the ALB URL**

```bash
kubectl get ingress -n retail-app
# Wait for ADDRESS to appear
```

**Step 10: Access the Store**

Open the ALB URL in your browser:
```bash
http://<ALB_ADDRESS>
```

---

### Verify Deployment

```bash
# Check all pods
kubectl get pods -n retail-app
```
### Expected output:

 NAME        READY   STATUS    RESTARTS   AGE
 carts       1/1     Running   0          5m
 catalog     1/1     Running   0          5m
 checkout    1/1     Running   0          5m 
 orders      1/1     Running   0          5m
 rabbitmq    1/1     Running   0          5m
 redis       1/1     Running   0          5m
 ui          1/1     Running   0          5m

### Check CloudWatch logs
```bash
kubectl get pods -n amazon-cloudwatch
```

---

##  CI/CD Pipeline Setup

### GitHub Secrets Configuration

Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Add the following secrets:

| **Secret Name** | **Value** | **Description** |
|--------------|-------------|------------|
| `AWS_ACCESS_KEY_ID` | `AKIA...` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | `wJalr...` | IAM user secret key |
 `DB_PASSWORD` | `YourSecurePassword123!` | Database password |

### Pipeline Triggers

| **Workflow** | **Trigger** | **Action** |
|--------------|-------------|------------|
|**Terraform Plan** | Pull Request (terraform/**) | Runs terraform plan and posts the output as a PR comment |
| **Terraform Apply** | Merge to or Push to main (terraform/**) | Runs terraform apply -auto-approve to update infrastructure |
| **Deploy Application** | Run after successful `Terraform Apply` or Push to main (kubernetes/**, lambda/**, scripts/deploy-app.sh) or manual (workflow_dispatch) | Executes deploy-app.sh to deploy the latest application version |

### Testing the Pipeline

1. **Test Terraform Plan:**

   ```bash
   git checkout -b test-terraform
   echo "# test" >> terraform/main.tf
   git add terraform/main.tf
   git commit -m "Test terraform plan"
   git push -u origin test-terraform
   ```
   Create a Pull Request on GitHub. The plan output should appear as a comment.

2. **Test Terraform Apply:**
   Merge the PR to main. The apply workflow should run.

3. **Test Deploy Application:**
   Push a change to any file in kubernetes/, lambda/, or scripts/. The deployment workflow should run. Or trigger manually on **GitHub Actions** 

---

##  Verification Steps

### 1. Check Pod Status

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
rabbitmq-xxxxxxxx-xxxxx    1/1     Running   0          5m
redis-xxxxxxxx-xxxxx       1/1     Running   0          5m
ui-xxxxxxxx-xxxxx          1/1     Running   0          5m
```

### 2. Verify Logging

```bash
# Check control plane logs
aws logs tail /aws/eks/project-bedrock-cluster/cluster --region us-east-1

# Check application logs
aws logs tail /aws/containerinsights/project-bedrock-cluster/application --region us-east-1

# List all project log groups
aws logs describe-log-groups --region us-east-1 --query 'logGroups[?contains(logGroupName, `project-bedrock`) || contains(logGroupName, `bedrock-asset`) || contains(logGroupName, `containerinsights`)].logGroupName' --output table

# Application logs
kubectl logs -n retail-app deployment/catalog --tail=20
```

### 3. Get ALB URL

```bash
kubectl get ingress -n retail-app
```

**Expected output:**

```
NAME                   CLASS    HOSTS   ADDRESS                                                                  PORTS   AGE
retail-store-ingress   <none>   *       k8s-retailap-retailst-xxxxxxxxxx-xxxxxxxxxx.us-east-1.elb.amazonaws.com   80      10m
```

### 4. Access the Store

Open the ALB URL in your browser:

```
http://k8s-retailap-retailst-xxxxxxxxxx-xxxxxxxxxx.us-east-1.elb.amazonaws.com
```

You should see the InnovateMart Retail Store homepage with product listings.

### 5. Test Store Functionality

- Browse products
- Add items to cart
- View cart
- Proceed to checkout

### 6. Test Serverless Extension

```bash
echo "test image content" > test-image.jpg
aws s3 cp test-image.jpg s3://bedrock-assets-YOUR-STUDENT-ID/ --profile bedrock-dev
```

**Check CloudWatch Logs:**

1. Go to AWS Console → CloudWatch → Log groups
2. Find `/aws/lambda/bedrock-asset-processor`
3. Look for log entry: `"Image received: test-image.jpg"`

### 7. Test Developer Access

```bash
# Configure developer profile
aws configure --profile bedrock-dev

# Update kubeconfig
aws eks update-kubeconfig --name project-bedrock-cluster --profile bedrock-dev --region us-east-1

# Test read access (should succeed)
kubectl get pods -n retail-app

# Test delete (should fail with Forbidden)
kubectl delete pod -n retail-app <any-pod>
```

---

##  Developer Access Setup

**IAM User:** `bedrock-dev-view`

This user has:

**- AWS Console:** `ReadOnlyAccess` managed policy
**- S3:** `s3:PutObject on bedrock-assets-*` bucket
**- Kubernetes:** `view` ClusterRole (read-only)

##  Credentials

###  Get credentials from Terraform output:

```bash
# Create new access keys
aws iam create-access-key --user-name bedrock-dev-view

# Or get from Terraform output
cd terraform
echo "Access Key: $(terraform output -raw dev_user_access_key)"
echo "Secret Key: $(terraform output -raw dev_user_secret_key)"
cd ..
```

### Kubernetes Access

The user is mapped to the view ClusterRole via the aws-auth ConfigMap. This is configured automatically by the deployment script.

---

##  Observability

### Control Plane Logs

Enabled in terraform/eks.tf:

```hcl
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

### Application Logs (FluentBit)

Deployed via EKS add-on in `amazon-cloudwatch` namespace:

```bash
kubectl get pods -n amazon-cloudwatch
```

### CloudWatch Log Groups

| **Log Group** | **Purpose** |
|---------|----------|
| `/aws/eks/project-bedrock-cluster/cluster` | Control plane logs |
| `/aws/containerinsights/project-bedrock-cluster/application` | Application container logs |
| `/aws/containerinsights/project-bedrock-cluster/performance` | Performance metrics |
| `/aws/lambda/bedrock-asset-processor` | Lambda function logs |

---

##  Troubleshooting

### Issue: Terraform Apply Hangs on EKS

**Solution:** Wait. EKS cluster creation takes 15-25 minutes.

### Issue: Pods in CrashLoopBackOff

**Solution:** Check logs:

```bash
kubectl logs -n retail-app deployment/<service> --tail=50
```

**Common causes:**

**- Wrong database credentials:** Verify Secrets Manager value
**- Missing MySQL driver:** Use Helm chart instead of raw manifest
**- Database not reachable**: Check security group rules

### Issue: ALB Not Provisioning

**Solution:** Check LB controller logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50
```

**Common causes:**

**- Missing CRDs:** Apply CRDs manually
**- RBAC permissions:** Update ClusterRole
**- IAM policy:** Check inline policy includes all required actions
**- VPC ID missing:** Verify `--aws-vpc-id` in controller args

### Issue: Terraform Destroy Fails

**Solution:** Manually clean up dependencies:

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

### Issue: Secrets Manager "Scheduled for Deletion" Error

**Solution:**

```bash
aws secretsmanager delete-secret \
  --secret-id project-bedrock-db-credentials \
  --force-delete-without-recovery \
  --region us-east-1
```

---

##  Destroy and Rebuild

### Automated Teardown

**To completely destroy all resources:**

```bash
chmod +x scripts/destroy-all.sh
./scripts/destroy-all.sh

# Or with custom database password
./scripts/destroy-all.sh "YourSecurePassword123!"
```

**What the script does:**

1. Uninstalls all Helm releases
2. Deletes Kubernetes namespaces
3. Removes LB controller and CRDs
4. Deletes EKS add-ons
5. Removes IAM access keys
6. Empties and deletes S3 buckets
7. Deletes ALBs, NAT Gateways, and releases Elastic IPs
8. Force-deletes Secrets Manager secrets
9. Force deletes VPC and all dependencies
10. Runs terraform destroy
11. Cleans up any remaining network interfaces and EIPs

⚠️ This permanently deletes all resources. Ensure you have backups of any data you need.

### Manual Teardown (if needed)

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

# 5. Re-run to confirm
terraform destroy -auto-approve -var="db_password=YourSecurePassword123!"
cd ..
```

### Verify Everything is Gone

```bash
aws eks describe-cluster --name project-bedrock-cluster 2>/dev/null || echo "✅ EKS deleted"
aws rds describe-db-instances --db-instance-identifier project-bedrock-mysql 2>/dev/null || echo "✅ RDS deleted"
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=project-bedrock-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "✅ VPC deleted"
```

### Full Rebuild

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

##  Useful Commands

### Kubernetes

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

### Helm

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

### Terraform

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

### AWS CLI

```bash
# Get RDS endpoints
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address]' --output table

# Get EKS cluster info
aws eks describe-cluster --name project-bedrock-cluster

# Get Secrets Manager value
aws secretsmanager get-secret-value --secret-id project-bedrock-db-credentials --query SecretString --output text | jq

# List all project log groups
aws logs describe-log-groups --region us-east-1 \
  --query 'logGroups[?contains(logGroupName, `project-bedrock`) || contains(logGroupName, `containerinsights`) || contains(logGroupName, `bedrock-asset`)].logGroupName' \
  --output table
```

---

##  Environment Variables Reference

| **Variable** | **Value** | **Description** |
|---------|----------|------| 
| `AWS_REGION` | `us-east-1` | AWS region |
| `CLUSTER_NAME` | `project-bedrock-cluster` | EKS cluster name |
| `NAMESPACE` | `retail-app` | Kubernetes namespace |
| `DB_USERNAME` | `admin MySQL` | MySQL username |
| `DB_PASSWORD` | `YourSecurePassword123!` | MySQL password|
| `DYNAMODB_TABLE` | `project-bedrock-retail-store` | DynamoDB table name |

---

##  Tags

All resources are tagged with:
```
Project: karatu-2025-capstone
```

---

##  Support

**For issues or questions:**

- Check the Troubleshooting section
- Review the AWS EKS Documentation
- Review the Terraform AWS Provider Documentation


