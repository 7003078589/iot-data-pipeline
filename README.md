🚀 Automated IoT Data Processing Pipeline
This project implements a robust, scalable, and automated pipeline for processing IoT sensor data on AWS. It demonstrates an event-driven architecture where raw data dropped into an S3 bucket is automatically picked up, transformed (e.g., temperature conversion, data enrichment), and stored in a processed data lake. A CI/CD pipeline ensures continuous delivery of the data processing logic.

✨ Features
Event-Driven Ingestion: Automatically triggers processing upon new file uploads to S3.

Scalable Data Transformation: Utilizes AWS ECS Fargate for serverless, containerized data processing, scaling automatically with data volume.

Data Validation: Checks for the presence and validity of critical data fields (e.g., temperature, humidity).

Data Transformation: Converts temperature from Celsius to Fahrenheit.

Data Enrichment: Adds location_id based on device_id lookup (simulated).

Data Filtering: Processes records only if they meet specified criteria (e.g., temperature above a threshold).

Robust Error Handling: Logs malformed or invalid records for later review.

Automated CI/CD: AWS CodePipeline and CodeBuild automate the build and deployment of the data processing application.

Infrastructure as Code (IaC): All AWS resources are defined and managed using Terraform.

🏗️ Architecture & Workflow
The pipeline operates as follows:

Raw Data Ingestion (AWS S3 - iot-raw-data-bucket): IoT devices or other data sources upload raw sensor data (e.g., sample_data.jsonl) to a designated S3 bucket.

Event Trigger (AWS S3 Event Notification): An S3 event notification is configured to trigger an AWS Lambda function whenever a new .jsonl file is created in the raw data bucket.

Task Orchestration (AWS Lambda - s3-event-handler): The Lambda function receives the S3 event, extracts the bucket and key of the new file, and then initiates an AWS ECS Fargate task. It passes the input and output S3 paths as environment variables to the Fargate task.

Data Processing (AWS ECS Fargate - iot-data-processor-container):

An ECS Fargate task runs a Docker container built from the app.py application.

The app.py script downloads the raw data file from S3.

It performs data validation (checks for numeric temperature, humidity).

It filters records (e.g., only processes temperatures above 10°C).

It enriches data (e.g., adds location_id based on device_id).

It transforms data (e.g., converts temperature to temp_fahrenheit).

It uploads the processed data to the designated processed data S3 bucket.

Processed Data Storage (AWS S3 - iot-processed-data-bucket): The transformed and validated data is stored here, ready for analytics, dashboards, or further downstream processing.

CI/CD (AWS CodePipeline & CodeBuild):

Source Stage: Monitors a GitHub repository for changes to the app/ directory.

Build Stage: AWS CodeBuild builds the Docker image from the app/Dockerfile and app/app.py, then pushes it to Amazon ECR (Elastic Container Registry).

🛠️ Technologies Used
AWS Services:

S3: Object storage for raw and processed data.

ECR: Docker container registry.

ECS (Fargate): Serverless compute for running the data processing application.

Lambda: Event-driven function to trigger ECS tasks.

IAM: Identity and Access Management for secure permissions.

CodePipeline: Orchestrates the CI/CD workflow.

CodeBuild: Builds and pushes Docker images.

CloudWatch: For logging and monitoring.

CodeStar Connections: Secure connection to GitHub for CodePipeline.

Containerization: Docker

Infrastructure as Code (IaC): Terraform

Programming Language: Python 3.9+ (for app.py and Lambda)

📂 Project Structure
iot-data-pipeline/
├── .gitignore
├── README.md
├── app/
│   ├── app.py
│   ├── Dockerfile
│   └── requirements.txt
├── lambda/
│   └── s3_event_handler.py
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── versions.tf

🚀 Getting Started
Follow these steps to deploy and run the pipeline in your AWS account.

Prerequisites
Before you begin, ensure you have the following installed and configured:

AWS CLI: Configured with credentials that have sufficient permissions to create and manage AWS resources.

Terraform: Install Terraform.

Docker: Install Docker.

Git: Install Git.

GitHub Repository: A GitHub repository (e.g., your-username/iot-data-pipeline) where you will push this project's code.

1. Clone the Repository
git clone https://github.com/your-username/iot-data-pipeline.git
cd iot-data-pipeline

(Replace your-username with your actual GitHub username or organization.)

2. Update Configuration Variables
Navigate to the terraform/ directory and update the variables.tf file.

cd terraform
# Open variables.tf in your editor

terraform/variables.tf:
Ensure the following variables are set correctly for your environment:

aws_region: Your desired AWS region (e.g., "us-east-1", "ap-south-1").

raw_data_bucket_name: MUST BE GLOBALLY UNIQUE. Choose a unique name (e.g., yourname-iot-raw-data-bucket-2025).

processed_data_bucket_name: MUST BE GLOBALLY UNIQUE. Choose a unique name (e.g., yourname-iot-processed-data-bucket-2025).

github_owner: YOUR EXACT GITHUB USERNAME or ORGANIZATION NAME. (e.g., "AmanKumar")

github_repo_name: The name of your GitHub repository (e.g., "iot-data-pipeline").

github_branch: The branch CodePipeline should monitor (e.g., "main").

3. Deploy Infrastructure with Terraform
From the terraform/ directory:

terraform init          # Initialize Terraform (downloads providers)
terraform plan          # Review the planned changes (ensure no errors)
terraform apply         # Apply the changes to deploy resources

Type yes when prompted to confirm the terraform apply.

4. IMPORTANT: Complete CodeStar Connection (Manual Step!)
After terraform apply completes, your CodePipeline's Source stage will be in a "Pending" state, waiting for you to authorize the connection to GitHub. This is a crucial one-time manual step:

Go to the AWS Management Console.

Navigate to CodePipeline.

In the left-hand navigation pane, under "Settings," click on Connections.

Find the connection named iot-data-pipeline-gh-conn (or similar, based on your project_name_prefix). Its status will be "Pending".

Click on the connection and follow the prompts to "Update pending connection" or "Connect to GitHub". This will redirect you to GitHub to authenticate and authorize AWS CodeStar Connections.

Once completed, the connection status will change to "Available".

5. Trigger the CI/CD Pipeline
Once the CodeStar Connection is "Available", your CodePipeline should automatically detect the code in your GitHub repository and start its first execution. If it doesn't, you can manually trigger it:

Go to your iot-data-pipeline-pipeline in the CodePipeline console.

Click the "Release change" button in the top right corner.

The pipeline will:

Source: Pull your code from GitHub.

Build: Build the Docker image from app/Dockerfile and app/app.py, then push it to your ECR repository.

6. Test the Data Processing Pipeline
Once the CodePipeline's "Build" stage is successful, your Docker image is ready. Now, let's test the end-to-end data processing:

Prepare a Sample Data File:
Create a file named sample_data.jsonl with the following content:

{"device_id": "sensor-alpha", "location": "warehouse-A", "temperature": 20.0, "humidity": 55.5, "pressure": 1012.3, "timestamp": "2025-07-11T11:00:00Z"}
{"device_id": "sensor-beta", "location": "warehouse-B", "temperature": 28.1, "humidity": 62.1, "pressure": 1010.5, "timestamp": "2025-07-11T11:01:00Z"}
{"device_id": "sensor-alpha", "location": "warehouse-A", "temperature": 22.5, "humidity": 58.0, "pressure": 1011.8, "timestamp": "2025-07-11T11:02:00Z"}
{"device_id": "sensor-gamma", "location": "server-room-1", "temperature": 18.7, "humidity": 45.0, "pressure": 1013.0, "timestamp": "2025-07-11T11:03:00Z"}
{"device_id": "sensor-beta", "location": "warehouse-B", "temperature": 26.9, "humidity": 60.5, "pressure": 1010.9, "timestamp": "2025-07-11T11:04:00Z"}

Upload to Raw Data S3 Bucket:
Upload this sample_data.jsonl file to your iot-raw-data-bucket-unique-aman-2025 S3 bucket.

Monitor Logs:

Go to AWS CloudWatch.

Check the log group for your Lambda function (/aws/lambda/iot-data-pipeline-s3-event-handler).

Check the log group for your ECS tasks (/ecs/iot-data-pipeline-data-processor). Look for messages indicating successful processing, temperature conversion, and enrichment.

Verify Processed Data:

Go to your iot-processed-data-bucket-unique-aman-2025 S3 bucket.

🧹 Cleanup
To avoid incurring AWS costs, remember to destroy your infrastructure when you are done:

cd terraform
terraform destroy

Type yes when prompted.

💡 Future Enhancements
Error Handling for Bad Records: Implement a Dead-Letter Queue (DLQ) for Lambda or a separate S3 bucket for bad_records to allow re-processing or manual inspection.

Data Lake Integration: Store processed data in a format like Parquet in a data lake (e.g., using AWS Glue Data Catalog and Athena) for easier querying.

Alerting: Set up CloudWatch Alarms for pipeline failures, ECS task errors, or high Lambda error rates.

More Complex Transformations: Integrate with AWS Glue for ETL jobs or use Apache Spark on EMR for large-scale processing.

Dashboarding: Create a dashboard (e.g., with Amazon QuickSight or Grafana) to visualize the processed IoT data.

Secure Secrets Management: Store sensitive information (if any) in AWS Secrets Manager and retrieve it at runtime.

✍️ Author
Aman Kumar
LinkedIn Profile
