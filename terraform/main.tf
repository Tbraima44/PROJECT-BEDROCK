# =============================================================================
# PROVIDER CONFIGURATIONS
# =============================================================================

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project = "karatu-2025-capstone"
      ManagedBy = "Terraform"
    }
  }
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
  depends_on = [aws_eks_cluster.main]
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
  depends_on = [aws_eks_cluster.main]
}

# TLS certificate for OIDC
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# =============================================================================
# AWS SECRETS MANAGER - Database Credentials
# =============================================================================

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "project-bedrock-db-credentials"
  description = "Database credentials for retail store application"
  
  tags = {
    Name    = "project-bedrock-db-credentials"
    Project = "karatu-2025-capstone"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    mysql_username     = var.db_username
    mysql_password     = var.db_password
    mysql_host         = aws_db_instance.mysql.endpoint
    mysql_port         = "3306"
    mysql_database     = "retaildb"
    postgresql_username = "dbadmin"
    postgresql_password = var.db_password
    postgresql_host    = aws_db_instance.postgresql.endpoint
    postgresql_port    = "5432"
    postgresql_database = "retaildb"
  })
}

# =============================================================================
# IAM POLICY - EKS Nodes to Access Secrets Manager
# =============================================================================

resource "aws_iam_policy" "secrets_manager_access" {
  name        = "project-bedrock-secrets-manager-access"
  description = "Allow EKS pods to access Secrets Manager for DB credentials"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [aws_secretsmanager_secret.db_credentials.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_secrets_manager" {
  policy_arn = aws_iam_policy.secrets_manager_access.arn
  role       = aws_iam_role.eks_node_group.name  # References role from eks.tf
}

# =============================================================================
# OIDC PROVIDER - For IRSA (IAM Roles for Service Accounts)
# =============================================================================

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  
  tags = {
    Name    = "project-bedrock-eks-oidc"
    Project = "karatu-2025-capstone"
  }
}

# resource "kubernetes_config_map_v1_data" "aws_auth" {
#   depends_on = [aws_eks_cluster.main]
#   metadata {
#     name      = "aws-auth"
#     namespace = "kube-system"
#   }
#   force = true
#   data = {
#     mapUsers = yamlencode([
#       {
#         userarn  = aws_iam_user.bedrock_dev_view.arn
#         username = "bedrock-dev-view"
#         groups   = ["view"]
#       }
#     ])
#   }
# }

# =============================================================================
# AWS LOAD BALANCER CONTROLLER - IRSA Setup
# =============================================================================

resource "aws_iam_role" "load_balancer_controller" {
  name = "project-bedrock-lb-controller-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
  
  tags = {
    Name    = "project-bedrock-lb-controller-role"
    Project = "karatu-2025-capstone"
  }
}

resource "aws_iam_role_policy" "load_balancer_controller" {
  name = "project-bedrock-lb-controller-policy"
  role = aws_iam_role.load_balancer_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = "*"
      }
    ]
  })
}# retrigger workflow
