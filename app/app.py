# app.py (Revised for S3 integration and local testing fallback)
import os
import json
import datetime
import sys
import logging
import boto3 # AWS SDK for Python

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Initialize S3 client
s3_client = boto3.client('s3')

def celsius_to_fahrenheit(celsius):
    """Converts Celsius to Fahrenheit."""
    return (celsius * 9/5) + 32

def process_s3_data(input_bucket, input_key, output_bucket, output_key):
    """
    Reads raw sensor data from an S3 object, transforms it, and writes
    the processed data to another S3 object.
    """
    processed_records = []
    
    logging.info(f"Attempting to read s3://{input_bucket}/{input_key}")
    try:
        # Get the object from S3
        response = s3_client.get_object(Bucket=input_bucket, Key=input_key)
        # Read content line by line
        lines = response['Body'].iter_lines()

        for line_bytes in lines:
            line = line_bytes.decode('utf-8').strip()
            if not line:
                continue # Skip empty lines
            try:
                record = json.loads(line)
                
                # Add processed timestamp
                record['processed_timestamp'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                
                # Convert temperature if 'temp_celsius' exists
                if 'temp_celsius' in record:
                    record['temp_fahrenheit'] = celsius_to_fahrenheit(record['temp_celsius'])
                
                processed_records.append(record)
                logging.debug(f"Processed record: {record}")
            except json.JSONDecodeError as e:
                logging.error(f"Skipping malformed JSON line: {line} - Error: {e}")
            except Exception as e:
                logging.error(f"Error processing line: {line} - Error: {e}")

        # Prepare data for writing to S3
        output_content = ""
        for record in processed_records:
            output_content += json.dumps(record) + '\n'

        # Write processed data to S3
        logging.info(f"Writing processed data to s3://{output_bucket}/{output_key}")
        s3_client.put_object(Bucket=output_bucket, Key=output_content.encode('utf-8')) # Using Body=output_content.encode('utf-8')
        
        logging.info(f"Successfully processed {len(processed_records)} records from {input_key} and saved to {output_key}.")

    except s3_client.exceptions.NoSuchKey:
        logging.error(f"Input object not found: s3://{input_bucket}/{input_key}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"An unexpected error occurred during S3 data processing: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # In a real Fargate task, these would be passed as environment variables
    # or command-line arguments.
    # For local testing, you can set them as dummy values or use actual S3 paths
    # if you have AWS credentials configured locally.

    # Example: Set these environment variables for local testing with real S3 buckets
    # export INPUT_BUCKET="your-raw-data-bucket"
    # export INPUT_KEY="raw/test_data.jsonl"
    # export OUTPUT_BUCKET="your-processed-data-bucket"
    # export OUTPUT_KEY="processed/output_data.jsonl"

    input_bucket = os.environ.get('INPUT_BUCKET')
    input_key = os.environ.get('INPUT_KEY')
    output_bucket = os.environ.get('OUTPUT_BUCKET')
    output_key = os.environ.get('OUTPUT_KEY')

    if not all([input_bucket, input_key, output_bucket, output_key]):
        logging.error("Missing required environment variables: INPUT_BUCKET, INPUT_KEY, OUTPUT_BUCKET, OUTPUT_KEY.")
        logging.info("Proceeding with local dummy data processing for demonstration.")
        
        # Simulate input data
        dummy_input_data = [
            {"device_id": "sensor-001", "temp_celsius": 25.5, "humidity": 60},
            {"device_id": "sensor-002", "temp_celsius": 30.0, "humidity": 65},
            {"device_id": "sensor-003", "temp_celsius": 20.1, "humidity": 55},
            "this is a bad line", # Malformed data to test error handling
            {"device_id": "sensor-004", "humidity": 70} # Missing temp_celsius
        ]
        local_input_file = "raw_sensor_data.jsonl"
        with open(local_input_file, 'w') as f:
            for item in dummy_input_data:
                if isinstance(item, dict):
                    f.write(json.dumps(item) + '\n')
                else:
                    f.write(item + '\n')

        local_output_file = "processed_sensor_data.jsonl"
        
        # A simplified local file processing function, not using S3 client
        def local_process_data(infile_path, outfile_path):
            processed_records = []
            with open(infile_path, 'r') as infile:
                for line in infile:
                    try:
                        record = json.loads(line.strip())
                        record['processed_timestamp'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                        if 'temp_celsius' in record:
                            record['temp_fahrenheit'] = celsius_to_fahrenheit(record['temp_celsius'])
                        processed_records.append(record)
                    except json.JSONDecodeError:
                        logging.warning(f"Skipping malformed line in local processing: {line.strip()}")
            with open(outfile_path, 'w') as outfile:
                for record in processed_records:
                    outfile.write(json.dumps(record) + '\n')
            logging.info(f"Local processing complete. Output in {outfile_path}")

        local_process_data(local_input_file, local_output_file)
        sys.exit(0) # Exit after local processing

    logging.info("Starting S3 data processing script...")
    process_s3_data(input_bucket, input_key, output_bucket, output_key)
    logging.info("S3 data processing script finished.")