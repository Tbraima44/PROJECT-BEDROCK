# 🚀 Project Bedrock – InnovateMart EKS Deployment

Production‑grade microservices platform on Amazon EKS, fully automated with Terraform, Kubernetes, GitHub Actions, and serverless components.

---

## 📌 Overview

**Company:** InnovateMart Inc.  
**Mission:** “Project Bedrock” – deliver a secure, observable, and scalable e‑commerce application using managed AWS services.  
**Architecture:** Microservices deployed on EKS with managed databases (RDS MySQL/PostgreSQL, DynamoDB), external ALB ingress, CloudWatch logging, and an event‑driven S3→Lambda pipeline.

---

## 🧱 Architecture Diagram

![alt text](docs/architecture.png)

- **VPC** `project-bedrock-vpc` with public/private subnets across 2 AZs
- **EKS Cluster** `project-bedrock-cluster` (v1.34+), 8× t3.micro nodes
- **Data Layer:** Amazon RDS (MySQL, PostgreSQL) in private subnets, DynamoDB table
- **Application:** Retail Store Sample App (`retail-app` namespace)
- **Ingress:** AWS Load Balancer Controller → Application Load Balancer (ALB)
- **Observability:** Control plane logs + FluentBit → CloudWatch
- **Serverless:** S3 bucket `bedrock-assets-[id]` → Lambda `bedrock-asset-processor` → CloudWatch

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
│   ├── observability/
│   │   └── fluentbit.yaml      # FluentBit DaemonSet (optional)
│   ├── rbac/
│   │   └── dev-view-role.yaml  # RBAC for bedrock-dev-view user access
│   ├── retail-store/           # Microservice Deployments, Services, Ingress, ExternalName services
│   │   ├── carts.yaml
│   │   ├── catalog.yaml
│   │   ├── checkout.yaml
│   │   ├── configmap.yaml      # (created dynamically by script)
│   │   ├── secret.yaml         # (created dynamically by script)
│   │   ├── db-external-services.yaml   # ExternalName services for managed DBs
│   │   ├── ingress.yaml
│   │   ├── orders.yaml
│   │   ├── rabbitmq.yaml
│   │   ├── redis.yaml
│   │   └── ui.yaml
│   └── namespace.yaml
│   
├── lambda/                     # Lambda function source
│   └── bedrock-asset-processor/
│       ├── index.py
│       └── requirements.txt
│
├── scripts/                    # Automation scripts
│   ├── deploy-app.sh           # Main application deployment script
│   ├── generate-grading-json.sh # Generate grading.json file
│   └── get-endpoints.sh
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


---

## 🔧 Prerequisites

### Local Machine
- **AWS CLI** (`aws configure` with admin credentials)
- **Terraform** ≥ 1.5.0
- **kubectl**
- **jq**, **openssl**
- **Git**

### AWS Account
- An S3 bucket for remote Terraform state (e.g., `project-bedrock-tfstate-[your-id]`).  
  *If it doesn’t exist, create it manually once.*

### GitHub Repository
- Add the following **repository secrets**:
  - `AWS_ACCESS_KEY_ID` – IAM user with admin permissions
  - `AWS_SECRET_ACCESS_KEY`
  - `DB_PASSWORD` – your chosen database password (e.g., `YourSecurePassword123!`)

---

## 🚀 Quick Start – Local Deployment

All commands are run from the repository root.

### 1. Set database password
```bash
export DB_PASSWORD="YourSecurePassword123!"   # Use your own strong password
```

### 2. Deploy infrastructure with Terraform

```bash
cd terraform
terraform init
terraform apply -auto-approve -var="db_password=$DB_PASSWORD"
cd ..
```

**Note:** The first apply creates a new VPC, EKS cluster (≈15‑20 min), RDS, etc. Remote state is stored in S3.

### 3. Deploy the application

```bash
./scripts/deploy-app.sh
```

This script will:

· Create the retail-app namespace, RBAC, and ExternalName services for databases
· Fetch RDS endpoints and credentials from AWS Secrets Manager
· Deploy all microservices with correct images and database connections
· Install the AWS Load Balancer Controller (with proper IAM and CRDs)
· Apply the Ingress and wait for the ALB

### 4. Get the application URL

```bash
kubectl get ingress -n retail-app
```

Open the ADDRESS in your browser – the retail store is live.

---

## 🤖 CI/CD Automation

The repository includes three GitHub Actions workflows:

| **Workflow** | **Trigger** | **Action** |
|--------------|-------------|------------|
|**Terraform Plan** | Pull Request (terraform/**) | Runs terraform plan and posts the output as a PR comment |
| **Terraform Apply** | Push to main (terraform/**) | Runs terraform apply -auto-approve to update infrastructure |
| **Deploy Application** | Push to main (kubernetes/**, lambda/**, scripts/**) or manual (workflow_dispatch) | Executes deploy-app.sh to deploy the latest application version |

After a successful pipeline run, download the grading.json artifact from the **Actions** tab → latest run → **Artifacts**.

---

## 🔐 Developer Access

An IAM user bedrock-dev-view is created with:

**· AWS Console:** ReadOnlyAccess policy
**· S3:** s3:PutObject on the assets bucket
**· Kubernetes:** view ClusterRole in retail-app namespace

Credentials are output by Terraform. To test:

```bash
aws configure --profile bedrock-dev    # use the access key/secret from Terraform output
aws eks update-kubeconfig --name project-bedrock-cluster --profile bedrock-dev
kubectl get pods -n retail-app         # succeeds
kubectl delete pod ... -n retail-app   # must FAIL
```

---

## 📊 Observability

· **EKS Control Plane Logs:** API, Audit, Authenticator, ControllerManager, Scheduler → CloudWatch
· **Application Logs:** FluentBit DaemonSet ships container logs to CloudWatch Logs group /aws/containerinsights/project-bedrock-cluster/application
· **CloudWatch Container Insights** is available via the EKS add‑on.

---

## ⚡ Serverless Extension

An S3 bucket bedrock-assets-[your-student-id] triggers a Lambda bedrock-asset-processor on object creation.
The Lambda logs "Image received: [filename]" to CloudWatch.
The bedrock-dev-view user can upload test files.

```bash
echo "test" > test.jpg
aws s3 cp test.jpg s3://bedrock-assets-[your-id]/ --profile bedrock-dev
```

Check CloudWatch logs for /aws/lambda/bedrock-asset-processor.

---

## 🧹 Cleanup

```bash
# Destroy all AWS resources
cd terraform
terraform destroy -auto-approve -var="db_password=$DB_PASSWORD"
cd ..
```

⚠️ **Important**: After destroy, you may need to manually release Elastic IPs and delete the S3 bucket if there are leftover versions. See the troubleshooting section.

---

## 🛠️ Known Issues & Troubleshooting

| **Symptom** | **Solution** |
|-------------|--------------|
| Pods stuck Pending with Too many pods | Increase desired_size in eks.tf to 8 or more; temporarily scale down fluentbit/redis/rabbitmq |
| ALB not getting address | Verify LB controller ClusterRole has all necessary permissions, CRDs are installed, and controller pod is Running |
| catalog/orders CrashLoopBackOff | Ensure ExternalName services catalog-db etc. exist and the database credentials (dbadmin) are correct |
| "AccessDenied" for LB controller | Update the inline IAM policy to include elasticloadbalancing:AddTags, ec2:CreateSecurityGroup and others |
| Lambda zip missing in CI | The workflow now packages the Lambda before Terraform apply |
| Secrets Manager "scheduled for deletion" | Force‑delete the secret: aws secretsmanager delete-secret --secret-id project-bedrock-db-credentials --force-delete-without-recovery |

---

## 💰 Cost Reminder

EKS clusters, NAT Gateways, RDS instances, and ALBs incur ongoing charges.
**Tear down resources** when not actively developing (terraform destroy).
The project uses 8 t3.micro nodes (Free Tier eligible, but combined usage may exceed free limits).

---

Built for the **InnovateMart** capstone – fully automated, secure, and production‑ready.

```