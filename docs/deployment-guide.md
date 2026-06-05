# Project Bedrock – InnovateMart EKS Deployment Guide

This document explains how to deploy the full InnovateMart retail store application on Amazon EKS, including managed databases, observability, event‑driven serverless components, and CI/CD automation.

---

## 📋 Prerequisites

· AWS account with administrative privileges (or an IAM user with sufficient permissions to create VPC, EKS, RDS, DynamoDB, IAM, S3, Lambda, etc.)
· AWS CLI installed and configured (aws configure)
· kubectl installed (https://kubernetes.io/docs/tasks/tools/)
· jq installed (https://stedolan.github.io/jq/)
· openssl available (usually pre‑installed on Linux/macOS)
· Terraform **1.5.0+** installed (https://developer.hashicorp.com/terraform/downloads)
· Git and a GitHub account for CI/CD (optional)

---

## 🗂️ Repository Structure

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

## 🔧 One‑Time Setup (Required Before First Deployment)

1. **Create the S3 bucket for Terraform remote state**
      (Replace <YOUR_STUDENT_ID> with your actual student ID.)
   ```bash
   aws s3api create-bucket --bucket project-bedrock-tfstate-<YOUR_STUDENT_ID> --region us-east-1
   aws s3api put-bucket-versioning --bucket project-bedrock-tfstate-<YOUR_STUDENT_ID> --versioning-configuration Status=Enabled
   aws s3api put-bucket-encryption --bucket project-bedrock-tfstate-<YOUR_STUDENT_ID> --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
   ```
2. **Set up GitHub repository secrets** (if using CI/CD):
   · AWS_ACCESS_KEY_ID : IAM admin user access key
   · AWS_SECRET_ACCESS_KEY : corresponding secret key
   · DB_PASSWORD : the database password (e.g., YourSecurePassword123!)
3. **Prepare** terraform/terraform.tfvars (for local runs) – do **not** commit this file.
      Example:
   ```hcl
   db_username = "dbadmin"
   db_password = "YourSecurePassword123!"
   student_id  = "your-student-id"
   ```

---

## 🚀 Deployment Options

### Option A: Fully Automated via GitHub Actions (recommended)

1. **Push to the** main **branch** – any change inside terraform/ triggers the Terraform Apply workflow.
      Ensure the repository secrets are set.
2. After the infrastructure is successfully applied, the **Deploy Application** workflow automatically starts (triggered by changes to kubernetes/, lambda/, or scripts/).
      It runs scripts/deploy-app.sh and sets up everything on the EKS cluster.
3. **Get the Application URL** from the workflow logs (final step of deploy-app.yaml) or later with:
   ```bash
   kubectl get ingress -n retail-app
   ```
4. **Download** grading.json **artifact** from the Terraform Apply workflow run (or generate locally – see below).

---

### Option B: Manual Deployment from CLI

1. **Initialize and apply Terraform**
   ```bash
   cd terraform
   terraform init
   terraform apply -var="db_password=YourSecurePassword123!"
   ```
   This creates the VPC, EKS cluster (8 nodes), RDS, DynamoDB, S3, Lambda, IAM roles, etc.
2. **Deploy the application**
   ```bash
   cd ..
   ./scripts/deploy-app.sh
   ```
   The script will:
   · Configure kubectl
   · Install the AWS Load Balancer Controller (with proper IAM permissions and CRDs)
   · Deploy all microservices, databases external services, and the Ingress
   · Update the Lambda function code
   · Output the Application URL when ready
3. **Generate** grading.json
   ```bash
   cd terraform
   terraform output -json > grading.json
   ```

---

## 🧪 Verifying the Deployment

**· Check pod status**
  ```bash
  kubectl get pods -n retail-app
  ```
  All pods should be Running.
**· Access the store** – open the ALB URL from the Ingress. The store should load without errors.
**· Test the developer IAM user** (bedrock-dev-view)
    Retrieve its credentials from Terraform output:
  ```bash
  cd terraform
  terraform output dev_user_access_key
  terraform output dev_user_secret_key
  ```
  Configure the AWS CLI with these keys, then:
  ```bash
  aws eks update-kubeconfig --name project-bedrock-cluster
  kubectl get pods -n retail-app          # works
  kubectl delete pod <any-pod> -n retail-app  # "Forbidden"
  ```
**· Test the S3‑Lambda event**
    Upload a file to the assets bucket:
  ```bash
  echo "test image" > test.jpg
  aws s3 cp test.jpg s3://bedrock-assets-<YOUR_STUDENT_ID>/ --profile bedrock-dev
  ```
  Check CloudWatch logs for /aws/lambda/bedrock-asset-processor – you’ll see "Image received: test.jpg".
**· Verify CI/CD pipeline**
    Open a pull request against main – the Terraform Plan workflow runs and posts the plan as a comment.

---

## 🧹 Cleanup

To avoid ongoing costs, destroy all resources when you are done.

### Option A: Destroy manually

```bash
cd terraform
terraform destroy -var="db_password=YourSecurePassword123!"
cd ..
```

### Option B: Let the CI/CD destroy (if configured)

Add a workflow that runs terraform destroy. (Not included by default.)

⚠️ The S3 assets bucket may need to be emptied first if it contains objects. The RDS secret in Secrets Manager might also need force‑deletion if it was previously scheduled for deletion.

---

## ❓ Troubleshooting Common Issues

| **Symptom** | **Likely Cause / Fix** |
|-------------|------------------------|
| terraform apply fails with “secret already scheduled for deletion” | Force‑delete the secret: aws secretsmanager delete-secret --secret-id project-bedrock-db-credentials --force-delete-without-recovery |
| Pods stuck in Pending or Too many pods | Increase node count to 8 (already set in eks.tf). If still hitting limits, remove FluentBit temporarily. |
| catalog or orders pods crashing with Access denied | Check the username in Secrets Manager – it must be dbadmin for MySQL and PostgreSQL. |
| catalog crashes with catalog-db: no such host | Ensure db-external-services.yaml is applied. |
| orders crashes with Failed to load driver class com.mysql.cj.jdbc.Driver | Use image tag 0.4.0 (the latest tag lacks MySQL driver). |
| Load Balancer Controller failing with no matches for kind "TargetGroupBinding" | Apply the CRDs before deploying the controller (already done by the script). |
| ALB address never appears | Check LB controller logs for permissions errors; verify the ClusterRole allows ingresses and targetgroupbindings resources. |
| Workflow fails with “Credentials could not be loaded” | Ensure AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY secrets are set in the repository. |
| Workflow fails with terraform: command not found in deploy step | The deploy script no longer uses Terraform – use the latest version from the repo. |

---

## 🔒 Security Notes

· The bedrock-dev-view IAM user has **read‑only** AWS console access and **S3 PutObject** to the assets bucket only.
· Kubernetes RBAC grants that user the view ClusterRole in the retail-app namespace.
· All database credentials are stored in AWS Secrets Manager.
· The Load Balancer Controller uses an IAM role with least‑privilege permissions (inline policy).
· RDS instances are placed in private subnets; only the VPC CIDR can access them.

---
