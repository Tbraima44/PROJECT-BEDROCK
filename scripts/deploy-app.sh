#!/bin/bash
set -e

echo "================================================================"
echo " InnovateMart Retail Store - Automated Deployment (Helm)"
echo "================================================================"

CLUSTER_NAME="project-bedrock-cluster"
REGION="us-east-1"
NAMESPACE="retail-app"

# ------------------------------------------------------------------
# 1. Prerequisites
# ------------------------------------------------------------------
echo "📋 Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl not found."
  exit 1
fi
if ! command -v helm &> /dev/null; then
  echo "⚙️  Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ------------------------------------------------------------------
# 2. Connect to EKS cluster
# ------------------------------------------------------------------
echo "🔗 Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
kubectl get nodes

# ------------------------------------------------------------------
# 3. Create namespace
# ------------------------------------------------------------------
echo "📁 Creating namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ------------------------------------------------------------------
# 4. RBAC for developer access
# ------------------------------------------------------------------
echo "🔐 Applying RBAC..."
kubectl apply -f kubernetes/rbac/dev-view-role.yaml
kubectl apply -f kubernetes/rbac/aws-load-balancer-controller-clusterrole.yaml

# ------------------------------------------------------------------
# 5. Fetch infrastructure endpoints
# ------------------------------------------------------------------
echo "📊 Fetching infrastructure endpoints..."
MYSQL_HOST=$(aws rds describe-db-instances --db-instance-identifier project-bedrock-mysql --query 'DBInstances[0].Endpoint.Address' --output text --region "$REGION")
DYNAMODB_TABLE="project-bedrock-retail-store"

# VPC ID for LB controller
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=project-bedrock-vpc" --query 'Vpcs[0].VpcId' --output text --region "$REGION")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$REGION")
LB_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/project-bedrock-lb-controller-role"

# ------------------------------------------------------------------
# 6. Get database credentials from Secrets Manager
# ------------------------------------------------------------------
echo "🔑 Retrieving database credentials..."
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id project-bedrock-db-credentials \
  --query SecretString \
  --output text \
  --region "$REGION")
MYSQL_USER=$(echo "$DB_SECRET" | jq -r '.mysql_username')
MYSQL_PASS=$(echo "$DB_SECRET" | jq -r '.mysql_password')

# ------------------------------------------------------------------
# 7. Install AWS Load Balancer Controller
# ------------------------------------------------------------------
echo "🌐 Installing AWS Load Balancer Controller..."

# CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/config/crd/bases/elbv2.k8s.aws_targetgroupbindings.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/config/crd/bases/elbv2.k8s.aws_ingressclassparams.yaml

# TLS cert
openssl req -x509 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -days 365 -nodes -subj "/CN=aws-load-balancer-controller"
kubectl create secret tls aws-load-balancer-tls --cert=/tmp/tls.crt --key=/tmp/tls.key -n kube-system --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/tls.key /tmp/tls.crt

# Clean up old controller
kubectl delete deployment aws-load-balancer-controller -n kube-system --ignore-not-found=true
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system --ignore-not-found=true

# ServiceAccount with IRSA
kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | \
  kubectl annotate --local -f - "eks.amazonaws.com/role-arn=${LB_ROLE_ARN}" --dry-run=client -o yaml | \
  kubectl apply -f -

# Controller deployment
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: aws-load-balancer-controller
  template:
    metadata:
      labels:
        app.kubernetes.io/name: aws-load-balancer-controller
    spec:
      serviceAccountName: aws-load-balancer-controller
      containers:
      - name: controller
        image: public.ecr.aws/eks/aws-load-balancer-controller:v2.7.0
        args:
        - --cluster-name=$CLUSTER_NAME
        - --ingress-class=alb
        - --aws-vpc-id=$VPC_ID
        - --enable-shield=false
        - --enable-waf=false
        - --enable-wafv2=false
        env:
        - name: AWS_REGION
          value: $REGION
        volumeMounts:
        - mountPath: /tmp/k8s-webhook-server/serving-certs
          name: cert
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
      volumes:
      - name: cert
        secret:
          secretName: aws-load-balancer-tls
EOF

kubectl wait --for=condition=available --timeout=120s deployment/aws-load-balancer-controller -n kube-system
echo "  ✅ LB Controller is running."

# ------------------------------------------------------------------
# 8. Deploy Retail Store with Helm
# ------------------------------------------------------------------
echo "📦 Deploying Retail Store with Helm..."

# Clone repo if not present
if [ ! -d "./retail-store-sample-app" ]; then
  git clone --depth=1 https://github.com/aws-containers/retail-store-sample-app.git
fi

# Deploy each service using the committed values file
echo "  🛒 Deploying carts..."
helm upgrade --install carts ./retail-store-sample-app/src/cart/chart/ \
  --namespace "$NAMESPACE" \
  --values kubernetes/helm/values.yaml

echo "  📚 Deploying catalog..."
helm upgrade --install catalog ./retail-store-sample-app/src/catalog/chart/ \
  --namespace "$NAMESPACE" \
  --values kubernetes/helm/values.yaml

echo "  📦 Deploying orders..."
helm upgrade --install orders ./retail-store-sample-app/src/orders/chart/ \
  --namespace "$NAMESPACE" \
  --values kubernetes/helm/values.yaml

echo "  💰 Deploying checkout..."
helm upgrade --install checkout ./retail-store-sample-app/src/checkout/chart/ \
  --namespace "$NAMESPACE" \
  --values kubernetes/helm/values.yaml

echo "  🖥️  Deploying UI..."
helm upgrade --install ui ./retail-store-sample-app/src/ui/chart/ \
  --namespace "$NAMESPACE"
  
# ------------------------------------------------------------------
# 9. Apply Ingress
# ------------------------------------------------------------------
echo "🚪 Applying Ingress..."
kubectl apply -f kubernetes/retail-store/ingress.yaml

# ------------------------------------------------------------------
# 10. Update Lambda
# ------------------------------------------------------------------
echo "⚡ Updating Lambda..."
cd lambda/bedrock-asset-processor
zip -r ../bedrock-asset-processor.zip index.py
cd ../..
aws lambda update-function-code --function-name bedrock-asset-processor --zip-file fileb://lambda/bedrock-asset-processor.zip --region "$REGION" --no-cli-pager

# ------------------------------------------------------------------
# 11. Wait for ALB
# ------------------------------------------------------------------
echo "⏳ Waiting for ALB..."
sleep 30
ATTEMPTS=0
MAX_ATTEMPTS=30
ALB_URL=""
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  ALB_URL=$(kubectl get ingress retail-store-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$ALB_URL" ] && break
  echo "  Waiting... attempt $((ATTEMPTS+1))/$MAX_ATTEMPTS"
  sleep 10
  ATTEMPTS=$((ATTEMPTS+1))
done

echo ""
echo "================================================================"
echo "🎉 Deployment complete!"
echo "================================================================"
[ -n "$ALB_URL" ] && echo "✅ Application URL: http://$ALB_URL" || echo "⚠️  Check manually: kubectl get ingress -n $NAMESPACE"
echo ""
kubectl get pods -n "$NAMESPACE"