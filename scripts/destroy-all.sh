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

# Delete login profile (console password)
echo "  Deleting login profile..."
aws iam delete-login-profile --user-name bedrock-dev-view --region "$REGION" 2>/dev/null || true

# ------------------------------------------------------------------
# 4. Empty S3 buckets
# ------------------------------------------------------------------
echo "🗑️  Emptying S3 buckets..."

# Assets bucket
BUCKET_NAME=$(aws s3 ls --region "$REGION" 2>/dev/null | grep "bedrock-assets" | awk '{print $3}')
if [ -n "$BUCKET_NAME" ]; then
  echo "  Emptying $BUCKET_NAME..."
  aws s3 rm "s3://$BUCKET_NAME" --recursive --region "$REGION" 2>/dev/null || true
  
  # Delete versions
  VERSIONS=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json --region "$REGION" 2>/dev/null || echo '{"Objects":[]}')
  aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$VERSIONS" --region "$REGION" 2>/dev/null || true
  
  # Delete markers
  MARKERS=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json --region "$REGION" 2>/dev/null || echo '{"Objects":[]}')
  aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$MARKERS" --region "$REGION" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 5. Force delete Secrets Manager secret
# ------------------------------------------------------------------
echo "🗑️  Deleting Secrets Manager secret..."
aws secretsmanager delete-secret --secret-id project-bedrock-db-credentials --force-delete-without-recovery --region "$REGION" 2>/dev/null || true

# ------------------------------------------------------------------
# 6. Force delete VPC dependencies (BEFORE Terraform destroy)
# ------------------------------------------------------------------
echo "🗑️  Pre-cleaning VPC dependencies..."

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=project-bedrock-vpc" --query 'Vpcs[0].VpcId' --output text --region "$REGION" 2>/dev/null || echo "")

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  echo "  Found VPC: $VPC_ID"

  # Delete ALBs
  echo "  Deleting ALBs..."
  for arn in $(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null); do
    [ -n "$arn" ] && aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "$REGION" && echo "    Deleted ALB" || true
  done
  sleep 30

  # Delete NAT Gateways
  echo "  Deleting NAT Gateways..."
  for ngw in $(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null); do
    [ -n "$ngw" ] && aws ec2 delete-nat-gateway --nat-gateway-id "$ngw" --region "$REGION" && echo "    Deleted NAT: $ngw" || true
  done
  echo "  Waiting for NAT Gateways to delete..."
  sleep 120

  # Release EIPs
  echo "  Releasing Elastic IPs..."
  for eip in $(aws ec2 describe-addresses --region "$REGION" --query 'Addresses[*].AllocationId' --output text 2>/dev/null); do
    [ -n "$eip" ] && aws ec2 release-address --allocation-id "$eip" --region "$REGION" 2>/dev/null && echo "    Released EIP" || true
  done

  # Delete ENIs
  echo "  Deleting network interfaces..."
  for eni in $(aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null); do
    [ -n "$eni" ] && aws ec2 delete-network-interface --network-interface-id "$eni" --region "$REGION" 2>/dev/null && echo "    Deleted ENI" || true
  done

  # Delete security groups
  echo "  Deleting security groups..."
  for sg in $(aws ec2 describe-security-groups --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null); do
    [ -n "$sg" ] && aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>/dev/null && echo "    Deleted SG" || true
  done

  # Delete route tables
  echo "  Deleting route tables..."
  for rt in $(aws ec2 describe-route-tables --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main==`false`].RouteTableId' --output text 2>/dev/null); do
    [ -n "$rt" ] && aws ec2 delete-route-table --route-table-id "$rt" --region "$REGION" 2>/dev/null && echo "    Deleted route table" || true
  done

  # Detach and delete IGW
  IGW_ID=$(aws ec2 describe-internet-gateways --region "$REGION" --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
  if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    echo "  Detaching and deleting IGW: $IGW_ID"
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION" 2>/dev/null || true
  fi

  # Delete subnets
  echo "  Deleting subnets..."
  for subnet in $(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
    [ -n "$subnet" ] && aws ec2 delete-subnet --subnet-id "$subnet" --region "$REGION" 2>/dev/null && echo "    Deleted subnet" || true
  done

  # Delete VPC with retries
echo "  Deleting VPC: $VPC_ID"
for i in $(seq 1 5); do
  if aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null; then
    echo "  ✅ VPC deleted"
    break
  fi
  echo "  Retrying VPC delete... ($i/5)"
  sleep 10
done

# ------------------------------------------------------------------
# 7. Terraform destroy (cleanup remaining resources)
# ------------------------------------------------------------------
echo "🗑️  Running Terraform destroy..."
cd "$(dirname "$0")/../terraform"
terraform init 2>/dev/null || true
terraform destroy -auto-approve -var="db_password=$DB_PASSWORD" 2>/dev/null || true

# ------------------------------------------------------------------
# 8. Final cleanup - Release any remaining EIPs and ENIs
# ------------------------------------------------------------------
echo "🗑️  Final cleanup..."

aws ec2 describe-addresses --region "$REGION" --query 'Addresses[*].AllocationId' --output text | tr '\t' '\n' | while read eip; do
  [ -n "$eip" ] && aws ec2 release-address --allocation-id "$eip" --region "$REGION" 2>/dev/null || true
done

aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=status,Values=available" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text | tr '\t' '\n' | while read eni; do
  [ -n "$eni" ] && aws ec2 delete-network-interface --network-interface-id "$eni" --region "$REGION" 2>/dev/null || true
done

echo ""
echo "================================================================"
echo "✅ Teardown complete!"
echo "================================================================"