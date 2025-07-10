# terraform/main.tf

# Configures the AWS provider with the specified region.
provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# VPC and Networking (Conditional: Creates if vpc_id is not provided)
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  count = var.vpc_id == "" ? 1 : 0 # Create VPC only if vpc_id is not provided

  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name_prefix}-vpc"
    Environment = "dev"
  }
}

resource "aws_internet_gateway" "main" {
  count = var.vpc_id == "" ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.project_name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count = var.vpc_id == "" ? length(var.availability_zones) : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = "10.0.${count.index}.0/24" # Example: 10.0.0.0/24, 10.0.1.0/24
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name_prefix}-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count = var.vpc_id == "" ? length(var.availability_zones) : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = "10.0.${count.index + 100}.0/24" # Example: 10.0.100.0/24, 10.0.101.0/24
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name_prefix}-private-subnet-${count.index}"
  }
}

resource "aws_eip" "nat_gateway" {
  count = var.vpc_id == "" ? length(var.availability_zones) : 0
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count         = var.vpc_id == "" ? length(var.availability_zones) : 0
  allocation_id = aws_eip.nat_gateway[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name_prefix}-nat-gateway-${count.index}"
  }
}

resource "aws_route_table" "public" {
  count = var.vpc_id == "" ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "${var.project_name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.vpc_id == "" ? length(aws_subnet.public) : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count = var.vpc_id == "" ? length(var.availability_zones) : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project_name_prefix}-private-rt-${count.index}"
  }
}

resource "aws_route_table_association" "private" {
  count          = var.vpc_id == "" ? length(aws_subnet.private) : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


locals {
  # Use existing VPC/subnets if provided, otherwise use newly created ones
  actual_vpc_id           = var.vpc_id != "" ? var.vpc_id : aws_vpc.main[0].id
  actual_private_subnet_ids = var.vpc_id != "" ? var.private_subnet_ids : [for s in aws_subnet.private : s.id]
  actual_public_subnet_ids  = var.vpc_id != "" ? var.public_subnet_ids : [for s in aws_subnet.public : s.id]
}


# -----------------------------------------------------------------------------
# S3 Buckets for Raw and Processed Data
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "raw_data" {
  bucket = var.raw_data_bucket_name
  tags = {
    Name        = "${var.project_name_prefix}-raw-data"
    Environment = "dev"
  }
}

# Removed aws_s3_bucket_acl.raw_data_acl as ACLs are not supported by default on new buckets
# resource "aws_s3_bucket_acl" "raw_data_acl" {
#   bucket = aws_s3_bucket.raw_data.id
#   acl    = "private"
# }

resource "aws_s3_bucket" "processed_data" {
  bucket = var.processed_data_bucket_name
  tags = {
    Name        = "${var.project_name_prefix}-processed-data"
    Environment = "dev"
  }
}

# Removed aws_s3_bucket_acl.processed_data_acl as ACLs are not supported by default on new buckets
# resource "aws_s3_bucket_acl" "processed_data_acl" {
#   bucket = aws_s3_bucket.processed_data.id
#   acl    = "private"
# }

# -----------------------------------------------------------------------------
# ECR Repository for Docker Image
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "data_processor_repo" {
  name = var.container_image_name

  image_tag_mutability = "MUTABLE" # Allows overwriting tags (e.g., 'latest')

  image_scanning_configuration {
    scan_on_push = true # Automatically scan images for vulnerabilities on push
  }

  tags = {
    Name        = "${var.project_name_prefix}-ecr-repo"
    Environment = "dev"
  }
}

# -----------------------------------------------------------------------------
# IAM Roles for ECS Task and Lambda Function
# -----------------------------------------------------------------------------

# IAM Role for ECS Task Execution (for ECS agent to pull images, log to CloudWatch)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name_prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name_prefix}-ecs-task-exec-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for ECS Task (for our app.py to access S3)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name_prefix}-ecs-task-role"
  }
}

resource "aws_iam_policy" "ecs_s3_access_policy" {
  name        = "${var.project_name_prefix}-ecs-s3-access-policy"
  description = "Allows ECS tasks to read from raw S3 bucket and write to processed S3 bucket."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject", # In case it needs to read its own writes or existing objects
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/ecs/${var.project_name_prefix}-data-processor:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_s3_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_s3_access_policy.arn
}

# IAM Role for Lambda Function (to run ECS tasks and log to CloudWatch)
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name_prefix}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name_prefix}-lambda-exec-role"
  }
}

resource "aws_iam_policy" "lambda_ecs_invoke_policy" {
  name        = "${var.project_name_prefix}-lambda-ecs-invoke-policy"
  description = "Allows Lambda to invoke ECS tasks and write CloudWatch logs."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTasks",
          "iam:PassRole" # Required to pass the ecs_task_role to ECS
        ],
        Resource = "*" # Restrict this further if possible in a production environment
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name_prefix}-s3-event-handler:*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces"
        ],
        Resource = "*" # Required for Lambda to create ENIs in VPC
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ecs_invoke_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_ecs_invoke_policy.arn
}

# -----------------------------------------------------------------------------
# ECS Cluster and Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "data_processor_cluster" {
  name = "${var.project_name_prefix}-cluster"

  tags = {
    Name        = "${var.project_name_prefix}-ecs-cluster"
    Environment = "dev"
  }
}

resource "aws_ecs_task_definition" "data_processor_task" {
  family                   = "${var.project_name_prefix}-data-processor-task"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  network_mode             = "awsvpc" # Required for Fargate
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn # For ECS agent
  task_role_arn            = aws_iam_role.ecs_task_role.arn            # For your app.py script

  container_definitions = jsonencode([
    {
      name      = "iot-data-processor-container", # This name must match in lambda/s3_event_handler.py
      image     = "${aws_ecr_repository.data_processor_repo.repository_url}:latest",
      cpu       = var.ecs_task_cpu,
      memory    = var.ecs_task_memory,
      essential = true,
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = "/ecs/${var.project_name_prefix}-data-processor",
          "awslogs-region"        = var.aws_region,
          "awslogs-stream-prefix" = "ecs"
        }
      }
      # Environment variables will be passed by Lambda's run_task override
      # E.g., INPUT_BUCKET, INPUT_KEY, OUTPUT_BUCKET, OUTPUT_KEY
    }
  ])

  tags = {
    Name = "${var.project_name_prefix}-ecs-task-def"
  }
}

# CloudWatch Log Group for ECS Task Logs
resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = "/ecs/${var.project_name_prefix}-data-processor"
  retention_in_days = 7 # Adjust as needed

  tags = {
    Name = "${var.project_name_prefix}-ecs-logs"
  }
}

# -----------------------------------------------------------------------------
# Lambda Function for S3 Event Trigger
# -----------------------------------------------------------------------------

# Create a zip file for the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda" # Points to the lambda directory
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "s3_event_handler" {
  function_name    = "${var.project_name_prefix}-s3-event-handler"
  handler          = "s3_event_handler.lambda_handler" # File name.function_name
  runtime          = "python3.9"
  role             = aws_iam_role.lambda_execution_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 300 # 5 minutes, adjust based on expected processing time
  memory_size      = 128 # Adjust as needed

  # Lambda needs to be in a VPC to invoke Fargate tasks in a VPC
  vpc_config {
    subnet_ids         = local.actual_private_subnet_ids # Lambda should be in private subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      ECS_CLUSTER_NAME        = aws_ecs_cluster.data_processor_cluster.name
      # Corrected: Refer to aws_ecs_task_definition.data_processor_task.arn
      ECS_TASK_DEFINITION_ARN = aws_ecs_task_definition.data_processor_task.arn
      PROCESSED_DATA_BUCKET_NAME = aws_s3_bucket.processed_data.bucket
      # Pass VPC subnets and security groups to Lambda for Fargate task launch
      SUBNET_IDS = join(",", local.actual_private_subnet_ids)
      SECURITY_GROUP_IDS = join(",", [aws_security_group.ecs_task_sg.id]) # Use ECS task SG
    }
  }

  tags = {
    Name = "${var.project_name_prefix}-lambda-handler"
  }
}

# CloudWatch Log Group for Lambda Logs
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.project_name_prefix}-s3-event-handler"
  retention_in_days = 7 # Adjust as needed

  tags = {
    Name = "${var.project_name_prefix}-lambda-logs"
  }
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "allow_s3_to_invoke_lambda" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_event_handler.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_data.arn
}

# S3 Event Notification to trigger Lambda (separate resource, as required)
resource "aws_s3_bucket_notification" "raw_data_notification" {
  bucket = aws_s3_bucket.raw_data.id

  # Correct block type: lambda_function
  lambda_function {
    # No 'id' needed here when embedded directly
    lambda_function_arn = aws_lambda_function.s3_event_handler.arn
    events              = ["s3:ObjectCreated:*"] # Trigger on any object creation
    filter_suffix       = ".jsonl"               # Only trigger for .jsonl files
  }

  # This depends_on is crucial to ensure the permission exists before the notification is set
  depends_on = [aws_lambda_permission.allow_s3_to_invoke_lambda]
}


# -----------------------------------------------------------------------------
# CI/CD Pipeline (CodePipeline, CodeBuild)
# -----------------------------------------------------------------------------

# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name_prefix}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name_prefix}-codebuild-role"
  }
}

# Policy for CodeBuild to push to ECR and log to CloudWatch
resource "aws_iam_policy" "codebuild_policy" {
  name        = "${var.project_name_prefix}-codebuild-policy"
  description = "Allows CodeBuild to push images to ECR and log to CloudWatch."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:GetAuthorizationToken" # Needed for docker login
        ],
        Resource = aws_ecr_repository.data_processor_repo.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/codebuild/${var.project_name_prefix}-codebuild:*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetObjectVersion"
        ],
        Resource = [
          aws_s3_bucket.codepipeline_artifacts.arn,
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

# CodeBuild Project
resource "aws_codebuild_project" "data_processor_build" {
  name          = "${var.project_name_prefix}-codebuild"
  description   = "Builds and pushes the Docker image for the data processor."
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = "5" # minutes

  artifacts {
    type = "CODEPIPELINE" # Artifacts are passed to CodePipeline
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL" # Or MEDIUM/LARGE depending on needs
    image        = "aws/codebuild/standard:5.0" # Use a standard image with Docker pre-installed
    type         = "LINUX_CONTAINER"
    privileged_mode = true # Required for Docker builds
    # Corrected: Use singular 'environment_variable' blocks
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.data_processor_repo.repository_url
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
  }

  source {
    type            = "CODEPIPELINE" # Source is provided by CodePipeline
    buildspec       = "app/buildspec.yml" # Path to buildspec.yml within the source repo
    git_clone_depth = 1
  }

  tags = {
    Name = "${var.project_name_prefix}-codebuild"
  }
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "${var.project_name_prefix}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name_prefix}-codepipeline-role"
  }
}

# Policy for CodePipeline to interact with S3, CodeBuild, and Secrets Manager
resource "aws_iam_policy" "codepipeline_policy" {
  name        = "${var.project_name_prefix}-codepipeline-policy"
  description = "Allows CodePipeline to interact with S3, CodeBuild, and Secrets Manager."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ],
        Resource = [
          aws_s3_bucket.codepipeline_artifacts.arn,
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:BatchGetBuilds"
        ],
        Resource = aws_codebuild_project.data_processor_build.arn
      },
      # Added permission for CodeStar Connections
      {
        Effect = "Allow",
        Action = [
          "codestar-connections:UseConnection"
        ],
        Resource = aws_codestarconnections_connection.github_connection.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy_attach" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}

# S3 Bucket for CodePipeline Artifacts
resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "${var.project_name_prefix}-codepipeline-artifacts-${data.aws_caller_identity.current.account_id}"
  # Removed deprecated 'acl' argument from here
  tags = {
    Name        = "${var.project_name_prefix}-codepipeline-artifacts"
    Environment = "dev"
  }
}

# Removed aws_s3_bucket_acl.codepipeline_artifacts_acl as ACLs are not supported by default on new buckets
# resource "aws_s3_bucket_acl" "codepipeline_artifacts_acl" {
#   bucket = aws_s3_bucket.codepipeline_artifacts.id
#   acl    = "private" # Recommended for artifact buckets
# }


# New resource for S3 bucket versioning
resource "aws_s3_bucket_versioning" "codepipeline_artifacts_versioning" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# CodeStar Connection for GitHub (Required for GitHub v2)
resource "aws_codestarconnections_connection" "github_connection" {
  # Shortened the name to comply with the 32-character limit
  name          = "${var.project_name_prefix}-gh-conn" # Example: "iot-data-pipeline-gh-conn"
  provider_type = "GitHub"

  tags = {
    Name = "${var.project_name_prefix}-github-connection"
  }
}


# CodePipeline
resource "aws_codepipeline" "data_processor_pipeline" {
  name     = "${var.project_name_prefix}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name            = "Source"
      category        = "Source"
      owner           = "AWS" # Changed from ThirdParty
      provider        = "CodeStarSourceConnection" # Changed from GitHub
      version         = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn      = aws_codestarconnections_connection.github_connection.arn # New for GitHub v2
        FullRepositoryId   = "${var.github_owner}/${var.github_repo_name}" # New for GitHub v2
        BranchName         = var.github_branch # Corrected: Changed from 'Branch' to 'BranchName'
        # Removed PollForSourceChanges as it's not supported with CodeStarSourceConnection
      }
    }
  }

  stage {
    name = "Build"
    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["SourceOutput"]
      output_artifacts = ["BuildOutput"] # This is just a placeholder, actual image pushed to ECR
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.data_processor_build.name
      }
    }
  }

  tags = {
    Name = "${var.project_name_prefix}-pipeline"
  }
}

# Data source to retrieve the GitHub PAT from Secrets Manager (NO LONGER USED FOR PIPELINE SOURCE)
# This data source is now redundant for the CodePipeline source stage as we are using CodeStar Connections.
# However, if you have other parts of your infrastructure that might need to retrieve this secret,
# you might keep it. For this specific pipeline, it's not directly consumed by the pipeline source.
# data "aws_secretsmanager_secret_version" "github_token" {
#   secret_id = var.github_token_secret_name
# }

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

# Security Group for ECS Fargate Tasks
resource "aws_security_group" "ecs_task_sg" {
  name        = "${var.project_name_prefix}-ecs-task-sg"
  description = "Security group for ECS Fargate tasks"
  vpc_id      = local.actual_vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this in production if tasks don't need inbound access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow all outbound traffic (e.g., to S3, ECR, CloudWatch)
  }

  tags = {
    Name = "${var.project_name_prefix}-ecs-task-sg"
  }
}

# Security Group for Lambda Function
resource "aws_security_group" "lambda_sg" {
  name        = "${var.project_name_prefix}-lambda-sg"
  description = "Security group for Lambda function in VPC"
  vpc_id      = local.actual_vpc_id

  # Lambda needs to be able to communicate with ECS service endpoints and S3
  # and also with CloudWatch Logs.
  # No ingress needed unless explicitly exposing something.
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true # Allow communication within the same security group
    description = "Allow internal SG communication"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow all outbound traffic (e.g., to S3, ECS, CloudWatch)
  }

  tags = {
    Name = "${var.project_name_prefix}-lambda-sg"
  }
}