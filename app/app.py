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
                logging.debug("Skipping empty line.")
                continue # Skip empty lines
            try:
                logging.debug(f"Attempting to parse line: '{line}'")
                record = json.loads(line)
                
                # IMPORTANT: Ensure the parsed 'record' is a dictionary before processing
                if not isinstance(record, dict):
                    logging.warning(f"Skipping non-dictionary record after JSON parsing: {record}")
                    continue

                # Add processed timestamp
                record['processed_timestamp'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                
                # Convert temperature if 'temperature' exists
                if 'temperature' in record:
                    # Check if temperature is a valid number before conversion
                    if isinstance(record['temperature'], (int, float)):
                        logging.info(f"Found temperature: {record['temperature']} (Celsius)")
                        record['temp_fahrenheit'] = celsius_to_fahrenheit(record['temperature'])
                        logging.info(f"Converted to Fahrenheit: {record['temp_fahrenheit']}")
                    else:
                        logging.warning(f"Temperature value is not a number: {record['temperature']}. Skipping conversion.")
                
                processed_records.append(record)
                logging.debug(f"Successfully processed and added record: {record}")
            except json.JSONDecodeError as e:
                logging.error(f"Skipping malformed JSON line: '{line}' - Error: {e}")
            except Exception as e:
                logging.error(f"Error processing line: '{line}' - Error: {e}")

        # Prepare data for writing to S3
        output_content = ""
        if not processed_records:
            logging.warning("No valid records were processed. Output file will be empty.")
        for record in processed_records:
            output_content += json.dumps(record) + '\n'

        # Write processed data to S3
        logging.info(f"Writing processed data to s3://{output_bucket}/{output_key}")
        s3_client.put_object(
            Bucket=output_bucket,
            Key=output_key,
            Body=output_content.encode('utf-8')
        )
        
        logging.info(f"Successfully processed {len(processed_records)} records from {input_key} and saved to {output_key}.")

    except s3_client.exceptions.NoSuchKey:
        logging.error(f"Input object not found: s3://{input_bucket}/{input_key}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"An unexpected error occurred during S3 data processing: {e}")
        sys.exit(1)

if __name__ == "__main__":
    input_bucket = os.environ.get('INPUT_BUCKET')
    input_key = os.environ.get('INPUT_KEY')
    output_bucket = os.environ.get('OUTPUT_BUCKET')
    output_key = os.environ.get('OUTPUT_KEY')

    if not all([input_bucket, input_key, output_bucket, output_key]):
        logging.error("Missing required environment variables: INPUT_BUCKET, INPUT_KEY, OUTPUT_BUCKET, OUTPUT_KEY.")
        logging.info("For local testing, ensure these are set or modify script to use dummy files.")
        logging.info("Proceeding with local dummy file processing for demonstration.")
        
        # Simulate input data (ensure this matches your expected S3 input format)
        dummy_input_data = [
            {"device_id": "sensor-001", "temperature": 25.5, "humidity": 60},
            {"device_id": "sensor-002", "temperature": 30.0, "humidity": 65},
            {"device_id": "sensor-003", "temperature": 20.1, "humidity": 55},
            "this is a bad line", # Malformed data to test error handling
            {"device_id": "sensor-004", "humidity": 70} # Missing temperature
        ]
        local_input_file = "raw_sensor_data.jsonl"
        with open(local_input_file, 'w') as f:
            for item in dummy_input_data:
                if isinstance(item, dict):
                    f.write(json.dumps(item) + '\n')
                else:
                    f.write(item + '\n')

        local_output_file = "processed_sensor_data.jsonl"
        
        def local_process_data(infile_path, outfile_path):
            processed_records = []
            with open(infile_path, 'r') as infile:
                for line in infile:
                    try:
                        record = json.loads(line.strip())
                        if not isinstance(record, dict):
                            logging.warning(f"Skipping non-dictionary record in local processing: {record}")
                            continue

                        record['processed_timestamp'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                        if 'temperature' in record:
                            if isinstance(record['temperature'], (int, float)):
                                record['temp_fahrenheit'] = celsius_to_fahrenheit(record['temperature'])
                            else:
                                logging.warning(f"Temperature value is not a number in local processing: {record['temperature']}. Skipping conversion.")
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
# This script is designed to be run in an AWS Lambda environment where it will process data from S3.