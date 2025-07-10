# terraform/variables.tf

# Defines input variables for our Terraform configuration.
# These variables allow us to customize the deployment without changing the main code.

variable "aws_region" {
  description = "The AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1" # You can change this to your preferred region (e.g., "ap-south-1" for Mumbai)
}

variable "project_name_prefix" {
  description = "A prefix for naming all resources to ensure uniqueness and organization."
  type        = string
  default     = "iot-data-pipeline"
}

variable "raw_data_bucket_name" {
  description = "Name for the S3 bucket where raw IoT data will be ingested."
  type        = string
  default     = "iot-raw-data-bucket-unique-aman-2025" # IMPORTANT: S3 bucket names must be globally unique. Choose a unique name!
}

variable "processed_data_bucket_name" {
  description = "Name for the S3 bucket where processed data will be stored."
  type        = string
  default     = "iot-processed-data-bucket-unique-aman-2025" # IMPORTANT: S3 bucket names must be globally unique. Choose a unique name!
}

variable "container_image_name" {
  description = "Name of the Docker image for our data processor."
  type        = string
  default     = "iot-data-processor"
}

variable "ecs_task_cpu" {
  description = "The number of CPU units for the ECS Fargate task."
  type        = number
  default     = 256 # 256 (.25 vCPU), 512 (.5 vCPU), 1024 (1 vCPU), etc.
}

variable "ecs_task_memory" {
  description = "The amount of memory (in MiB) for the ECS Fargate task."
  type        = number
  default     = 512 # 512 (0.5 GB), 1024 (1 GB), 2048 (2 GB), etc.
}

variable "vpc_id" {
  description = "The ID of an existing VPC to deploy ECS tasks into. Leave empty to create a new one."
  type        = string
  default     = "" # If empty, a new VPC will be created.
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks. Required if using an existing VPC."
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (for NAT Gateway if creating new VPC). Required if using an existing VPC."
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones to use for VPC and subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"] # Adjust based on your chosen region
}

# --- CI/CD Variables ---
variable "github_owner" {
  description = "The GitHub owner (username or organization) of the repository."
  type        = string
  # IMPORTANT: Replace with your GitHub username or organization name
  default     = "7003078589"
}

variable "github_repo_name" {
  description = "The name of the GitHub repository."
  type        = string
  # IMPORTANT: Replace with your repository name (e.g., 'iot-data-pipeline')
  default     = "iot-data-pipeline"
}

variable "github_branch" {
  description = "The branch in the GitHub repository to monitor for changes."
  type        = string
  default     = "main" # Or 'master', depending on your repo
}

variable "github_token_secret_name" {
  description = "The name of the AWS Secrets Manager secret storing your GitHub Personal Access Token."
  type        = string
  # IMPORTANT: You will need to manually create this secret in AWS Secrets Manager
  # before applying Terraform. The secret value should be your GitHub PAT.
  default     = "github/codepipeline/token" # Example name, choose your own
}