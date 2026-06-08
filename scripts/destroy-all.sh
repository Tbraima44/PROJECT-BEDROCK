#!/bin/bash
set -e

echo "================================================================"
echo " Project Bedrock - Complete Teardown"
echo "================================================================"

REGION="us-east-1"
CLUSTER_NAME="project-bedrock-cluster"
DB_PASSWORD="${1:-YourSecurePassword123!}"

# ------------------------------------------------------------------
# 1. Delete application resources
# ------------------------------------------------------------------
echo "🗑️  Deleting application..."

# Uninstall Helm releases
helm uninstall ui catalog carts orders checkout -n retail-app 2>/dev/null || true
helm uninstall rabbitmq redis -n retail-app 2>/dev/null || true

# Delete namespaces
kubectl delete namespace retail-app --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace amazon-cloudwatch --ignore-not-found=true 2>/dev/null || true

# Delete LB controller
kubectl delete deployment aws-load-balancer-controller -n kube-system --ignore-not-found=true 2>/dev/null || true
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system --ignore-not-found=true 2>/dev/null || true
kubectl delete secret aws-load-balancer-tls -n kube-system --ignore-not-found=true 2>/dev/null || true
kubectl delete clusterrolebinding aws-load-balancer-controller --ignore-not-found=true 2>/dev/null || true
kubectl delete clusterrole aws-load-balancer-controller --ignore-not-found=true 2>/dev/null || true

# Delete CRDs
kubectl delete crd targetgroupbindings.elbv2.k8s.aws --ignore-not-found=true 2>/dev/null || true
kubectl delete crd ingressclassparams.elbv2.k8s.aws --ignore-not-found=true 2>/dev/null || true

# ------------------------------------------------------------------
# 2. Delete EKS add-ons
# ------------------------------------------------------------------
echo "🗑️  Deleting EKS add-ons..."
aws eks delete-addon --cluster-name "$CLUSTER_NAME" --addon-name amazon-cloudwatch-observability --region "$REGION" 2>/dev/null || true
aws eks delete-addon --cluster-name "$CLUSTER_NAME" --addon-name coredns --region "$REGION" 2>/dev/null || true
aws eks delete-addon --cluster-name "$CLUSTER_NAME" --addon-name vpc-cni --region "$REGION" 2>/dev/null || true
aws eks delete-addon --cluster-name "$CLUSTER_NAME" --addon-name kube-proxy --region "$REGION" 2>/dev/null || true

# ------------------------------------------------------------------
# 3. Delete IAM access keys
# ------------------------------------------------------------------
echo "🗑️  Deleting IAM access keys..."
for key in $(aws iam list-access-keys --user-name bedrock-dev-view --query 'AccessKeyMetadata[*].AccessKeyId' --output text --region "$REGION" 2>/dev/null); do
  echo "  Deleting key: $key"
  aws iam delete-access-key --user-name bedrock-dev-view --access-key-id "$key" --region "$REGION" 2>/dev/null || true
done

# ------------------------------------------------------------------
# 4. Empty S3 buckets
# ------------------------------------------------------------------
echo "🗑️  Emptying S3 buckets..."

# Assets bucket
BUCKET_NAME=$(aws s3 ls --region "$REGION" 2>/dev/null | grep "bedrock-assets" | awk '{print $3}')
if [ -n "$BUCKET_NAME" ]; then
  echo "  Emptying $BUCKET_NAME..."
  aws s3 rm "s3://$BUCKET_NAME" --recursive --region "$REGION" 2>/dev/null || true
  
  # Delete versions and markers
  aws s3api delete-objects --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json --region "$REGION" 2>/dev/null || echo '{"Objects":[]}')" \
    --region "$REGION" 2>/dev/null || true
    
  aws s3api delete-objects --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json --region "$REGION" 2>/dev/null || echo '{"Objects":[]}')" \
    --region "$REGION" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 5. Pre-cleanup network resources
# ------------------------------------------------------------------
echo "🗑️  Cleaning up network resources..."

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=project-bedrock-vpc" --query 'Vpcs[0].VpcId' --output text --region "$REGION" 2>/dev/null || echo "")

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  # Delete ALBs
  echo "  Deleting ALBs..."
  aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null | xargs -n1 aws elbv2 delete-load-balancer --load-balancer-arn --region "$REGION" 2>/dev/null || true

  # Delete NAT Gateways
  echo "  Deleting NAT Gateways..."
  aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null | xargs -n1 aws ec2 delete-nat-gateway --nat-gateway-id --region "$REGION" 2>/dev/null || true
  
  echo "  Waiting for NAT Gateways to delete..."
  sleep 120

  # Release EIPs
  echo "  Releasing Elastic IPs..."
  aws ec2 describe-addresses --region "$REGION" --query 'Addresses[*].AllocationId' --output text 2>/dev/null | xargs -n1 aws ec2 release-address --allocation-id --region "$REGION" 2>/dev/null || true

  # Delete network interfaces
  echo "  Deleting network interfaces..."
  aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null | xargs -n1 aws ec2 delete-network-interface --network-interface-id --region "$REGION" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 6. Force delete Secrets Manager secret
# ------------------------------------------------------------------
echo "🗑️  Deleting Secrets Manager secret..."
aws secretsmanager delete-secret --secret-id project-bedrock-db-credentials --force-delete-without-recovery --region "$REGION" 2>/dev/null || true

# ------------------------------------------------------------------
# 7. Terraform destroy
# ------------------------------------------------------------------
echo "🗑️  Running Terraform destroy..."
cd "$(dirname "$0")/../terraform"
terraform init 2>/dev/null || true
terraform destroy -auto-approve -var="db_password=$DB_PASSWORD" 2>/dev/null || true

# ------------------------------------------------------------------
# 8. Clean up remaining resources
# ------------------------------------------------------------------
echo "🗑️  Final cleanup..."

# Delete remaining EIPs
aws ec2 describe-addresses --region "$REGION" --query 'Addresses[*].AllocationId' --output text 2>/dev/null | xargs -n1 aws ec2 release-address --allocation-id --region "$REGION" 2>/dev/null || true

# Delete remaining network interfaces
aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=status,Values=available" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null | xargs -n1 aws ec2 delete-network-interface --network-interface-id --region "$REGION" 2>/dev/null || true

echo ""
echo "================================================================"
echo "✅ Teardown complete!"
echo "================================================================"
