# Dockerfile
# Use a lightweight official Python runtime as a parent image
FROM python:3.9-slim-buster

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file into the container at /app
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container at /app
COPY . .

# Entrypoint for the application.
# The actual S3 input/output keys will be passed as environment variables
# when the Fargate task runs.
ENTRYPOINT ["python", "app.py"]

# Expose the port the app runs on (if applicable) 