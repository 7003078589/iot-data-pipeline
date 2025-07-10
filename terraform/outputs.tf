# terraform/outputs.tf

# Defines output values that will be displayed after Terraform applies the configuration.
# These outputs are useful for verifying deployment and for use in other configurations (e.g., CI/CD).

output "raw_data_bucket_name" {
  description = "The name of the S3 bucket for raw data."
  value       = aws_s3_bucket.raw_data.bucket
}

output "processed_data_bucket_name" {
  description = "The name of the S3 bucket for processed data."
  value       = aws_s3_bucket.processed_data.bucket
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository."
  value       = aws_ecr_repository.data_processor_repo.repository_url
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster."
  value       = aws_ecs_cluster.data_processor_cluster.name
}

output "ecs_task_definition_arn" {
  description = "The ARN of the ECS task definition."
  value       = aws_ecs_task_definition.data_processor_task.arn
}

output "lambda_function_name" {
  description = "The name of the Lambda function."
  value       = aws_lambda_function.s3_event_handler.function_name
}

output "vpc_id" {
  description = "The ID of the VPC used."
  value       = local.actual_vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs used."
  value       = local.actual_private_subnet_ids
}

output "ecs_task_security_group_id" {
  description = "The ID of the security group for ECS tasks."
  value       = aws_security_group.ecs_task_sg.id
}