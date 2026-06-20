# 🏗️ Project Bedrock - InnovateMart EKS Deployment

**Production-Grade Microservices on AWS EKS**


---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Infrastructure Details](#infrastructure-details)
- [Application Deployment](#application-deployment)
- [CI/CD Pipeline](#cicd-pipeline)
- [Security](#security)
- [Observability](#observability)
- [Serverless Extension](#serverless-extension)
- [Developer Access](#developer-access)
- [Cleanup](#cleanup)

---

## Overview

**Company:** InnovateMart Inc.  
**Project:** Project Bedrock  
**Mission:** Deploy a production-grade microservices architecture on AWS EKS for the Retail Store application.

This project provisions a secure Amazon EKS cluster, deploys the AWS Retail Store Sample App, replaces in-cluster databases with managed AWS services (RDS MySQL, DynamoDB), implements CI/CD automation, and extends the architecture with serverless components.

### Key Features

- ✅ Infrastructure as Code (Terraform) with remote state management
- ✅ EKS cluster with managed node groups (t3.small instances)
- ✅ Managed databases (RDS MySQL, DynamoDB) replacing in-cluster databases
- ✅ Helm-based application deployment
- ✅ AWS Load Balancer Controller with ALB Ingress
- ✅ GitHub Actions CI/CD pipeline
- ✅ Developer IAM user with read-only access
- ✅ CloudWatch logging and observability
- ✅ Serverless Lambda function triggered by S3 uploads
- ✅ Security groups, Secrets Manager, and least-privilege IAM

---

## Architecture

![Architecture](docs/architecture.png)

---

## 📁 Repository Structure

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
│   │   └── values.yaml                 # Helm values for managed databases
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


## Prerequisites

- **AWS CLI** configured with admin credentials
- **Terraform** >= 1.5.0
- **kubectl** >= 1.28
- **Helm** >= 3.12
- **jq** (JSON processor)
- **GitHub account** with repository secrets configured

### AWS Requirements

- AWS account with AdministratorAccess
- AWS CLI configured:
  ```bash
  aws configure
  # Access Key ID, Secret Access Key, region: us-east-1, output: json
  ```

### GitHub Requirements

- GitHub repository with Actions enabled
- Repository secrets configured (see CI/CD Pipeline)

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/Tbraima44/PROJECT-BEDROCK.git
cd PROJECT-BEDROCK
```

### 2. Configure Database Password

```bash
chmod +x scripts/setup-credentials.sh
./scripts/setup-credentials.sh "YourSecurePassword123!"
```

Edit terraform/terraform.tfvars and set your student_id.

### 3. Create Remote State Bucket (if not exists)

```bash
aws s3api create-bucket \
  --bucket project-bedrock-tfstate-YOUR-STUDENT-ID \
  --region us-east-1
```

### 4. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan -var="db_password=YourSecurePassword123!"
terraform apply -auto-approve -var="db_password=YourSecurePassword123!"
cd ..
```
**Expected time:** 15-25 minutes

### 5. Deploy Application

```bash
./scripts/deploy-app.sh
```

### 6. Access the Store

**Get the ALB URL:**

```bash
kubectl get ingress -n retail-app
```

Open the ADDRESS in your browser.

---

##  Infrastructure Details

### VPC Configuration

| **Resource** | **Details** |
|--------------|-------------|
| **VPC Name** | project-bedrock-vpc|
| **CIDR** | 10.0.0.0/16 |
| **Public Subnets** | 2 (across AZs) |
| **Private Subnets** | 2 (across AZs) |
| **NAT Gateway** | 1 |

### EKS Cluster

| **Resource** | **Details** |
|--------------|-------------|
| **Cluster Name** | project-bedrock-cluster |
| **Kubernetes Version** | 1.34 |
| **Instance Type** | t3.small (2 vCPU, 2 GiB) |
| **Node Count** | 3 (max 5, min 2) |
| **Pod Capacity** | ~33 pods (11 per node)|

### Managed Databases

| **Service** | **Engine** | **Purpose** |
|------------|------------|------------|
| **RDS MySQL** | MySQL 8.0 | Carts, Catalog, Orders |
| **DynamoDB** | DynamoDB | Checkout |

### Other Resources

| **Resource** | **Name** |
|--------------|-------------|
| **S3 Bucket** | bedrock-assets-YOUR-STUDENT-ID |
| **Lambda** | bedrock-asset-processor |
| **Secrets Manager** | project-bedrock-db-credentials |
| **IAM User** | bedrock-dev-view |

---

##  Application Deployment

### Helm-Based Deployment

The retail store application is deployed using **Helm charts** with a custom `values.yaml` that disables in-cluster databases and points to managed AWS services.

**Values file:** kubernetes/helm/values.yaml

```yaml
mysql:
  enabled: false
dynamodb:
  enabled: false

    carts:
  datasource:
    url: "jdbc:mysql://MYSQL_HOST_PLACEHOLDER:3306/retaildb?useSSL=false&allowPublicKeyRetrieval=true"
    username: "MYSQL_USER_PLACEHOLDER"
    password: "MYSQL_PASS_PLACEHOLDER"
# ... similar for catalog, orders, checkout
```

**Single command deployment:**

```bash
helm upgrade --install carts ./retail-store-sample-app/src/cart/chart/ \
  --namespace retail-app --values kubernetes/helm/values.yaml
```

All **services** (carts, catalog, orders, checkout, ui) are deployed with the same pattern.

### Services

| **Service** | **Database** | **Chart** |
|------------|------------|------------| 
| **UI** | N/A | retail-store-app-charts/ui/chart/ |
| **Carts** | RDS MySQL | retail-store-app-charts/cart/chart/ |
| **Catalog** | RDS MySQL | retail-store-app-charts/catalog/chart/ |
| **Orders** | RDS MySQL | retail-store-app-charts/orders/chart/ |
| **Checkout** | DynamoDB | retail-store-app-charts/checkout/chart/ |
| **RabbitMQ** | N/A | Static manifest |
| **Redis** | N/A | Static manifest |

### Kubernetes Namespaces

| **Namespace** | **Purpose** |
|-----------|---------|
| `retail-app` | Application microservices (carts, catalog, orders, checkout, ui, rabbitmq, redis) |
| `amazon-cloudwatch` | Observability (FluentBit, CloudWatch agent, controller) |
| `kube-system` | System components (LB controller, CoreDNS, kube-proxy) |

### Ingress

An Application Load Balancer (ALB) is provisioned via the AWS Load Balancer Controller:

```bash
kubectl apply -f kubernetes/retail-store/ingress.yaml
```

---

##  CI/CD Pipeline

### GitHub Actions Workflows

| **Workflow** | **Trigger** | **Action** |
|--------------|-------------|------------|
|**Terraform Plan** | Pull Request (terraform/**) | Runs terraform plan and posts the output as a PR comment |
| **Terraform Apply** | Merge to or Push to main (terraform/**) | Runs terraform apply -auto-approve to update infrastructure |
| **Deploy Application** | Run after successful `Terraform Apply` or Push to main (kubernetes/**, lambda/**, scripts/deploy-app.sh) or manual (workflow_dispatch) | Executes deploy-app.sh to deploy the latest application version |

### Required GitHub Secrets

| **Secret** | **Description** |
|--------------|-------------| 
| **AWS_ACCESS_KEY_ID** | AWS IAM user access key |
| **AWS_SECRET_ACCESS_KEY** | AWS IAM user secret key |
| **DB_PASSWORD** | Database password for RDS |

## Triggering the Pipeline

### Terraform Plan:

```bash
git checkout -b test-terraform
echo "# test" >> terraform/main.tf
git add terraform/main.tf
git commit -m "Test plan"
git push -u origin test-terraform
# Create a PR on GitHub
```

**Terraform Apply:** Merge the PR to `main`.

**Deploy Application:** Push changes to `kubernetes/`, `lambda/`, or `scripts/`.

---

##  Security

### IAM

- **EKS Cluster Role:** `AmazonEKSClusterPolicy, AmazonEKSVPCResourceController`
- **EKS Node Role:** `AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly`
- **LB Controller Role:** Custom inline policy with ELB, EC2, and IAM permissions (IRSA)
- **Developer User (bedrock-dev-view):** `ReadOnlyAccess + s3:PutObject` on assets bucket

###  Kubernetes RBAC

- Developer user mapped to view ClusterRole (read-only across all namespaces)
- AWS LB Controller has dedicated ClusterRole with ingress and target group binding permissions

### Secrets Management

- Database credentials stored in AWS Secrets Manager
- Never hardcoded in source files committed to repository

### Network Security

- RDS instances in private subnets
- Security groups restrict database access to EKS node/pod CIDR only
- ALB in public subnets with internet-facing scheme

---

##  Observability

### CloudWatch Logs

- **Control plane logs:** API, Audit, Authenticator, ControllerManager, Scheduler
- **Application logs:** Fluent Bit DaemonSet ships container logs to CloudWatch
- **Lambda logs:** /aws/lambda/bedrock-asset-processor

View Logs

```bash
# Control plane
aws logs tail /aws/eks/project-bedrock-cluster/cluster --follow

# Application
aws logs tail /aws/containerinsights/project-bedrock-cluster/application --follow

# Specific pod
kubectl logs -n retail-app deployment/catalog --tail=50 -f
```

---

##  Serverless Extension

### S3 → Lambda Trigger

When a file is uploaded to bedrock-assets-YOUR-STUDENT-ID, the Lambda function bedrock-asset-processor is triggered.

**Lambda code:** lambda/bedrock-asset-processor/index.py

```python
def handler(event, context):
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    print(f"Image received: {key}")
    return {'statusCode': 200, 'body': f'Successfully processed {key}'}
```

**Test:**

```bash
echo "test image" > test.jpg
aws s3 cp test.jpg s3://bedrock-assets-YOUR-STUDENT-ID/ --profile bedrock-dev
# Check CloudWatch Logs for the Lambda function to see the log entry.
```

---

##  Developer Access

**IAM User:** bedrock-dev-view

| **Access** | **Details** |
|--------------|-------------| 
| **AWS Console** | `ReadOnlyAccess` |
| **S3** | `s3:PutObject` on bedrock-assets-* bucket|
| **Kubernetes** | `view` ClusterRole (read-only) |

### Configure Developer Profile

```bash
# Get credentials
cd terraform
terraform output -raw dev_user_access_key
terraform output -raw dev_user_secret_key
cd ..

# Configure profile
aws configure --profile bedrock-dev

# Update kubeconfig
aws eks update-kubeconfig --name project-bedrock-cluster --profile bedrock-dev --region us-east-1

# Test (should succeed)
kubectl get pods -n retail-app

# Test (should fail with Forbidden)
kubectl delete pod -n retail-app <any-pod>
```

---

## 🗑️ Cleanup

### Delete Application Resources

```bash
helm uninstall carts catalog orders checkout ui -n retail-app
kubectl delete namespace retail-app
```

##  Destroy Infrastructure

```bash
cd terraform
terraform destroy -auto-approve -var="db_password=YourSecurePassword123!"
cd ..
```

⚠️ **Note:** You may need to manually delete the ALB, release Elastic IPs, and delete network interfaces before Terraform destroy can complete. See troubleshooting section if destroy fails.

## Destroy All (To destroy all AWS resources and clean up the environment)

```bash
# Automated teardown (handles ALB, NAT Gateway, EIPs, S3, IAM keys, etc.)
chmod +x scripts/destroy-all.sh && ./scripts/destroy-all.sh

# Or with a custom database password
./scripts/destroy-all.sh "YourSecurePassword123!"
```

---

### Generating grading.json

```bash
cd terraform
terraform output -json > ../grading.json
```

---

##  Troubleshooting

### Terraform Destroy Fails

1. Delete the ALB manually:
   ```bash
   aws elbv2 delete-load-balancer --load-balancer-arn <ARN>
   ```
2. Release Elastic IPs:
   ```bash
   aws ec2 release-address --allocation-id <ALLOC_ID>
   ```
3. Delete network interfaces:
   ```bash
   aws ec2 delete-network-interface --network-interface-id <ENI_ID>
   ```
4. Retry destroy.

### Pods CrashLoopBackOff

**Check logs:**

```bash
kubectl logs -n retail-app deployment/<service> --tail=50
```

Common issues:

- Wrong database credentials → Check Secrets Manager
- Database not reachable → Check security group rules


### ALB Not Provisioning

**Check LB controller logs:**

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=30
```

**Common issues:**

- Missing CRDs → Apply CRDs manually
- RBAC permissions → Update ClusterRole
- IAM policy missing actions → Update inline policy

---

##  Tags

All resources are tagged with:

```
Project: karatu-2025-capstone
```

---

##  License

This project is created for the Karatu 2025 Capstone program.

---

##  Contact

- **Student-Id:** ALT-SOE-025-3778
- **Repository:** https://github.com/Tbraima44/PROJECT-BEDROCK
- **Application URL:** [ALB URL after deployment]
