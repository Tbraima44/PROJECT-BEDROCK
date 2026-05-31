# Input variables for Project Bedrock infrastructure
variable "student_id" {
  description = "Student ID for unique resource naming"
  type        = string
  default     = "alt-soe-025-3778" # Replace with actual student ID
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "eks_cluster_name" {
  description = "EKS Cluster Name"
  type        = string
  default     = "project-bedrock-cluster"
}

variable "vpc_name" {
  description = "VPC Name Tag"
  type        = string
  default     = "project-bedrock-vpc"
}

variable "eks_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}