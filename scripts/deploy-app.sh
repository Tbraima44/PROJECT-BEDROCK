#!/bin/bash
set -e

echo "================================================================"
echo " InnovateMart Retail Store - Automated Deployment"
echo "================================================================"

CLUSTER_NAME="project-bedrock-cluster"
REGION="us-east-1"
NAMESPACE="retail-app"

# ------------------------------------------------------------------
# 1. Prerequisites: kubectl, helm (for FluentBit if needed later)
# ------------------------------------------------------------------
echo "📋 Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl not found. Please install it first."
  exit 1
fi

# Helm is only needed if we decide to use it for FluentBit, but we have a static manifest now.
# We'll skip Helm install to keep things simple.

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
# 4. RBAC for developer read-only access
# ------------------------------------------------------------------
echo "🔐 Applying RBAC..."
kubectl apply -f kubernetes/rbac/dev-view-role.yaml
kubectl apply -f kubernetes/retail-store/db-external-services.yaml
# ------------------------------------------------------------------
# 5. Get endpoints from Terraform outputs
# ------------------------------------------------------------------
echo "📊 Fetching infrastructure endpoints..."

cd terraform
MYSQL_FULL=$(terraform output -raw mysql_endpoint)
POSTGRES_FULL=$(terraform output -raw postgresql_endpoint)
DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name)
VPC_ID=$(terraform output -raw vpc_id)
LB_ROLE_ARN=$(terraform output -raw load_balancer_controller_role_arn)
cd ..

# Extract host and port for JDBC URLs
MYSQL_HOST=$(echo $MYSQL_FULL | cut -d: -f1)
MYSQL_PORT=$(echo $MYSQL_FULL | cut -d: -f2)
POSTGRES_HOST=$(echo $POSTGRES_FULL | cut -d: -f1)
POSTGRES_PORT=$(echo $POSTGRES_FULL | cut -d: -f2)

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
POSTGRES_USER=$(echo "$DB_SECRET" | jq -r '.postgresql_username')
POSTGRES_PASS=$(echo "$DB_SECRET" | jq -r '.postgresql_password')

# ------------------------------------------------------------------
# 7. Create ConfigMap and Secrets
# ------------------------------------------------------------------
echo "⚙️  Creating ConfigMap and Secrets..."

kubectl create configmap retail-store-config \
  --namespace="$NAMESPACE" \
  --from-literal=MYSQL_HOST="$MYSQL_HOST" \
  --from-literal=MYSQL_PORT="$MYSQL_PORT" \
  --from-literal=MYSQL_DATABASE=retaildb \
  --from-literal=POSTGRES_HOST="$POSTGRES_HOST" \
  --from-literal=POSTGRES_PORT="$POSTGRES_PORT" \
  --from-literal=POSTGRES_DATABASE=retaildb \
  --from-literal=DYNAMODB_TABLE="$DYNAMODB_TABLE" \
  --from-literal=AWS_REGION="$REGION" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic retail-store-secrets \
  --namespace="$NAMESPACE" \
  --from-literal=MYSQL_USERNAME="$MYSQL_USER" \
  --from-literal=MYSQL_PASSWORD="$MYSQL_PASS" \
  --from-literal=POSTGRES_USERNAME="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# ------------------------------------------------------------------
# 8. Deploy Retail Store Microservices (corrected images + args)
# ------------------------------------------------------------------
echo "📦 Deploying Retail Store from local manifests..."

# Apply all YAML files in kubernetes/retail-store/ that we've already crafted
# They include the correct image tags (v0.4.0) and args for DB overrides.
kubectl apply -f kubernetes/retail-store/ --namespace="$NAMESPACE"

# ------------------------------------------------------------------
# Temporarily scale down non‑critical services to free pod slots
# ------------------------------------------------------------------
echo "  📉 Temporarily freeing pod capacity..."
for svc in rabbitmq redis checkout orders; do
  kubectl scale deployment $svc -n "$NAMESPACE" --replicas=0 --timeout=30s 2>/dev/null || true
done
sleep 5

# ------------------------------------------------------------------
# 9. Install AWS Load Balancer Controller (dynamic VPC ID, pod capacity aware)
# ------------------------------------------------------------------
echo "🌐 Installing AWS Load Balancer Controller..."

# Generate TLS certificate for webhook (needed even if disabled, to avoid crash)
openssl req -x509 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -days 365 -nodes -subj "/CN=aws-load-balancer-controller"
kubectl create secret tls aws-load-balancer-tls --cert=/tmp/tls.crt --key=/tmp/tls.key -n kube-system --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/tls.key /tmp/tls.crt

# Get dynamic values from Terraform
LB_ROLE_ARN=$(cd terraform && terraform output -raw load_balancer_controller_role_arn)
VPC_ID=$(cd terraform && terraform output -raw vpc_id)

# Clean up previous controller
kubectl delete deployment aws-load-balancer-controller -n kube-system --ignore-not-found=true
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system --ignore-not-found=true

# Create ServiceAccount with IRSA annotation
kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | \
  kubectl annotate --local -f - "eks.amazonaws.com/role-arn=${LB_ROLE_ARN}" --dry-run=client -o yaml | \
  kubectl apply -f -

# Create ClusterRole and ClusterRoleBinding
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: aws-load-balancer-controller
rules:
- apiGroups: ["", "extensions"]
  resources: ["configmaps", "endpoints", "events", "ingresses", "ingresses/status", "services", "pods/status"]
  verbs: ["create", "get", "list", "update", "watch", "patch"]
- apiGroups: ["", "extensions"]
  resources: ["nodes", "pods", "secrets", "services", "namespaces"]
  verbs: ["get", "list", "watch"]
---
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

# Deploy controller with WAF/Shield disabled
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/component: controller
      app.kubernetes.io/name: aws-load-balancer-controller
  template:
    metadata:
      labels:
        app.kubernetes.io/component: controller
        app.kubernetes.io/name: aws-load-balancer-controller
    spec:
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
        ports:
        - containerPort: 9443
          name: webhook-server
          protocol: TCP
        volumeMounts:
        - mountPath: /tmp/k8s-webhook-server/serving-certs
          name: cert
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
      volumes:
      - name: cert
        secret:
          defaultMode: 420
          secretName: aws-load-balancer-tls
      serviceAccountName: aws-load-balancer-controller
      terminationGracePeriodSeconds: 10
EOF

kubectl wait --for=condition=available --timeout=120s deployment/aws-load-balancer-controller -n kube-system
echo "  ✅ LB Controller is running."

# Wait for the controller to be ready
echo "  ⏳ Waiting for LB controller to start..."
kubectl wait --for=condition=available --timeout=120s deployment/aws-load-balancer-controller -n kube-system

echo "  ✅ LB Controller is running."

# Scale back up retail services (important for Ingress targets)
echo "  📈 Scaling retail services back up..."
for svc in carts catalog checkout orders rabbitmq redis ui; do
  kubectl scale deployment $svc -n "$NAMESPACE" --replicas=1 --timeout=30s 2>/dev/null || true
done

# ------------------------------------------------------------------
# 10. Apply Ingress (after LB controller is ready)
# ------------------------------------------------------------------
echo "🚪 Applying Ingress..."
kubectl apply -f kubernetes/retail-store/ingress.yaml

# ------------------------------------------------------------------
# 11. Deploy FluentBit for logging (optional – may be removed if capacity is tight)
# ------------------------------------------------------------------
echo "📊 Deploying FluentBit..."
kubectl apply -f kubernetes/observability/fluentbit.yaml --namespace=amazon-cloudwatch || true
# Note: FluentBit is a DaemonSet, so it uses 1 pod per node. If pod capacity is low, you can keep it commented out.

# ------------------------------------------------------------------
# 12. Update Lambda function code
# ------------------------------------------------------------------
echo "⚡ Packaging and updating Lambda..."
cd lambda/bedrock-asset-processor
zip -r ../../bedrock-asset-processor.zip index.py
cd ../..
aws lambda update-function-code \
  --function-name bedrock-asset-processor \
  --zip-file fileb://bedrock-asset-processor.zip \
  --region "$REGION" \
  --no-cli-pager

# ------------------------------------------------------------------
# 13. Wait for ALB and print the URL
# ------------------------------------------------------------------
echo "⏳ Waiting for ALB to be provisioned..."
sleep 30
ATTEMPTS=0
MAX_ATTEMPTS=30
ALB_URL=""
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  ALB_URL=$(kubectl get ingress retail-store-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$ALB_URL" ]; then
    break
  fi
  echo "  Waiting... attempt $((ATTEMPTS+1))/$MAX_ATTEMPTS"
  sleep 10
  ATTEMPTS=$((ATTEMPTS+1))
done

echo ""
echo "================================================================"
echo "🎉 Deployment complete!"
echo "================================================================"
if [ -n "$ALB_URL" ]; then
  echo "✅ Application URL: http://$ALB_URL"
else
  echo "⚠️  ALB still not ready. Check manually:"
  echo "   kubectl get ingress -n $NAMESPACE"
fi
echo ""
echo "📊 Pod status:"
kubectl get pods -n "$NAMESPACE"