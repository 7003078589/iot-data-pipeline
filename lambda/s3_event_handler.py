# lambda/s3_event_handler.py
import os
import json
import boto3
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Initialize AWS clients
ecs_client = boto3.client('ecs')
# Replace with your actual cluster name from Terraform outputs
ECS_CLUSTER_NAME = os.environ.get('ECS_CLUSTER_NAME')
# Replace with your actual task definition ARN from Terraform outputs
ECS_TASK_DEFINITION_ARN = os.environ.get('ECS_TASK_DEFINITION_ARN')
# Replace with your actual subnet IDs (from your VPC)
SUBNET_IDS = os.environ.get('SUBNET_IDS').split(',') if os.environ.get('SUBNET_IDS') else []
# Replace with your actual security group IDs (from your VPC)
SECURITY_GROUP_IDS = os.environ.get('SECURITY_GROUP_IDS').split(',') if os.environ.get('SECURITY_GROUP_IDS') else []

def lambda_handler(event, context):
    """
    AWS Lambda function that triggers an ECS Fargate task
    in response to an S3 ObjectCreated event.
    """
    logging.info(f"Received S3 event: {json.dumps(event)}")

    if not event or 'Records' not in event:
        logging.error("Invalid S3 event structure.")
        return {
            'statusCode': 400,
            'body': json.dumps('Invalid S3 event structure')
        }

    for record in event['Records']:
        if record['eventSource'] == 'aws:s3' and record['eventName'].startswith('ObjectCreated'):
            bucket_name = record['s3']['bucket']['name']
            object_key = record['s3']['object']['key']
            
            logging.info(f"New object created: s3://{bucket_name}/{object_key}")

            try:
                # Run the ECS Fargate task
                response = ecs_client.run_task(
                    cluster=ECS_CLUSTER_NAME,
                    launchType='FARGATE',
                    taskDefinition=ECS_TASK_DEFINITION_ARN,
                    count=1, # Run one instance of the task
                    platformVersion='LATEST',
                    networkConfiguration={
                        'awsvpcConfiguration': {
                            'subnets': SUBNET_IDS,
                            'securityGroups': SECURITY_GROUP_IDS,
                            'assignPublicIp': 'ENABLED' # Assign a public IP for outbound internet access (e.g., to S3)
                        }
                    },
                    overrides={
                        'containerOverrides': [
                            {
                                'name': 'iot-data-processor-container', # Must match the container name in your ECS Task Definition
                                'environment': [
                                    {'name': 'INPUT_BUCKET', 'value': bucket_name},
                                    {'name': 'INPUT_KEY', 'value': object_key},
                                    {'name': 'OUTPUT_BUCKET', 'value': os.environ.get('PROCESSED_DATA_BUCKET_NAME')}, # Get from Lambda env var
                                    {'name': 'OUTPUT_KEY', 'value': f"processed/{object_key.split('/')[-1]}"} # Example: processed/my_file.jsonl
                                ]
                            },
                        ],
                    }
                )
                logging.info(f"Successfully launched ECS task: {response['tasks'][0]['taskArn']}")
            except Exception as e:
                logging.error(f"Error launching ECS task for {object_key}: {e}")
                raise # Re-raise the exception to indicate failure to Lambda

    return {
        'statusCode': 200,
        'body': json.dumps('ECS task triggered successfully')
    }