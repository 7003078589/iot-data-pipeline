# Use an official Python runtime from Amazon ECR Public Gallery as a parent image
# This avoids Docker Hub unauthenticated pull rate limits.
FROM public.ecr.aws/docker/library/python:3.9-slim-buster

# Set the working directory in the container
WORKDIR /app

# Install any needed packages specified in requirements.txt
# Copy requirements.txt first to leverage Docker cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container
COPY . .

# Command to run the application
# The script will be executed when the ECS task starts.
# It expects environment variables to be passed at runtime (e.g., from Lambda).
CMD ["python", "app.py"]