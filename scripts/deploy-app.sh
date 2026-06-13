#!/bin/bash
set -e

echo "================================================================"
echo " InnovateMart Retail Store - Automated Deployment (Helm)"
echo "================================================================"

CLUSTER_NAME="project-bedrock-cluster"
REGION="us-east-1"
NAMESPACE="retail-app"

# Paths
CHARTS_DIR="./retail-store-app-charts"
VALUES_FILE="./kubernetes/helm/values.yaml"

# ------------------------------------------------------------------
# 1. Prerequisites
# ------------------------------------------------------------------
echo "📋 Checking prerequisites..."
command -v kubectl &> /dev/null || { echo "❌ kubectl not found."; exit 1; }
command -v helm &> /dev/null || { curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; }

# ------------------------------------------------------------------
# 2. Connect to EKS cluster
# ------------------------------------------------------------------
echo "🔗 Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# ------------------------------------------------------------------
# 3. Create namespace
# ------------------------------------------------------------------
echo "📁 Creating namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ------------------------------------------------------------------
# 4. Get infrastructure values
# ------------------------------------------------------------------
echo "📊 Fetching infrastructure endpoints..."
MYSQL_HOST=$(aws rds describe-db-instances --db-instance-identifier project-bedrock-mysql --query 'DBInstances[0].Endpoint.Address' --output text --region "$REGION")
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=project-bedrock-vpc" --query 'Vpcs[0].VpcId' --output text --region "$REGION")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$REGION")

# ------------------------------------------------------------------
# 5. Get database credentials
# ------------------------------------------------------------------
echo "🔑 Retrieving database credentials..."
DB_SECRET=$(aws secretsmanager get-secret-value --secret-id project-bedrock-db-credentials --query SecretString --output text --region "$REGION")
MYSQL_USER=$(echo "$DB_SECRET" | jq -r '.mysql_username')
MYSQL_PASS=$(echo "$DB_SECRET" | jq -r '.mysql_password')

# ------------------------------------------------------------------
# 6. Install AWS Load Balancer Controller
# ------------------------------------------------------------------
echo "🌐 Installing AWS Load Balancer Controller..."

# Apply CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/config/crd/bases/elbv2.k8s.aws_targetgroupbindings.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/config/crd/bases/elbv2.k8s.aws_ingressclassparams.yaml

# Apply RBAC
kubectl apply -f kubernetes/rbac/aws-load-balancer-controller-clusterrole.yaml

# Generate TLS cert
openssl req -x509 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -days 365 -nodes -subj "/CN=aws-load-balancer-controller"
kubectl create secret tls aws-load-balancer-tls --cert=/tmp/tls.crt --key=/tmp/tls.key -n kube-system --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/tls.key /tmp/tls.crt

# Clean up and create ServiceAccount with IRSA
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system --ignore-not-found=true
kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | \
  kubectl annotate --local -f - "eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/project-bedrock-lb-controller-role" --dry-run=client -o yaml | \
  kubectl apply -f -

# Create ClusterRoleBinding
kubectl delete clusterrolebinding aws-load-balancer-controller --ignore-not-found=true
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

# Add developer view permissions to aws-auth configmap
kubectl patch configmap aws-auth -n kube-system --type merge -p '{"data":{"mapUsers":"- userarn: arn:aws:iam::'$ACCOUNT_ID':user/bedrock-dev-view\n  username: bedrock-dev-view\n  groups:\n  - view"}}'

# Deploy controller with dynamic VPC ID
kubectl delete deployment aws-load-balancer-controller -n kube-system --ignore-not-found=true
sed "s/--aws-vpc-id=.*/--aws-vpc-id=$VPC_ID/" kubernetes/aws-load-balancer-controller/deployment.yaml | kubectl apply -f -

kubectl wait --for=condition=available --timeout=120s deployment/aws-load-balancer-controller -n kube-system
echo "  ✅ LB Controller is running."

# ------------------------------------------------------------------
# 7. Deploy Retail Store with Helm (using local charts and values.yaml)
# ------------------------------------------------------------------
echo "🚀 Deploying Retail Store with Helm..."

echo "  🛒 Deploying carts..."
helm upgrade --install carts "${CHARTS_DIR}/cart/chart/" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

echo "  📚 Deploying catalog..."
helm upgrade --install catalog "${CHARTS_DIR}/catalog/chart/" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

echo "  📦 Deploying orders..."
helm upgrade --install orders "${CHARTS_DIR}/orders/chart/" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

echo "  💰 Deploying checkout..."
helm upgrade --install checkout "${CHARTS_DIR}/checkout/chart/" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

echo "  🖥️  Deploying UI..."
helm upgrade --install ui "${CHARTS_DIR}/ui/chart/" \
  --namespace "$NAMESPACE"

# ------------------------------------------------------------------
# 8. Deploy RabbitMQ and Redis
# ------------------------------------------------------------------
echo "  🐰 Deploying RabbitMQ..."
kubectl apply -f kubernetes/retail-store/rabbitmq.yaml

echo "  📦 Deploying Redis..."
kubectl apply -f kubernetes/retail-store/redis.yaml

# ------------------------------------------------------------------
# 9. Enable CloudWatch Observability
# ------------------------------------------------------------------
echo "📊 Enabling CloudWatch Observability..."
aws eks create-addon --cluster-name "$CLUSTER_NAME" --addon-name amazon-cloudwatch-observability --region "$REGION" 2>/dev/null || echo "Add-on may already exist"

# ------------------------------------------------------------------
# 10. Apply RBAC and Ingress
# ------------------------------------------------------------------
echo "🔐 Applying RBAC..."
kubectl apply -f kubernetes/rbac/dev-view-role.yaml

echo "🚪 Applying Ingress..."
kubectl apply -f kubernetes/retail-store/ingress.yaml

# ------------------------------------------------------------------
# 11. Update Lambda
# ------------------------------------------------------------------
echo "⚡ Updating Lambda..."
cd lambda/bedrock-asset-processor && zip -r ../bedrock-asset-processor.zip index.py && cd ../..
aws lambda update-function-code --function-name bedrock-asset-processor --zip-file fileb://lambda/bedrock-asset-processor.zip --region "$REGION" --no-cli-pager

# ------------------------------------------------------------------
# 12. Wait for ALB
# ------------------------------------------------------------------
echo "⏳ Waiting for ALB..."
sleep 30
for i in $(seq 1 30); do
  ALB_URL=$(kubectl get ingress retail-store-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$ALB_URL" ] && break
  echo "  Waiting... $i/30"
  sleep 10
done

echo ""
echo "================================================================"
echo "🎉 Deployment complete!"
echo "================================================================"
[ -n "$ALB_URL" ] && echo "✅ Application URL: http://$ALB_URL" || echo "⚠️  Check manually: kubectl get ingress -n $NAMESPACE"
echo ""
kubectl get pods -n "$NAMESPACE"