#!/bin/bash
set -e

echo "======================================"
echo "Building Lambda Package with Docker"
echo "======================================"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running"
    echo "Please start Docker and try again"
    exit 1
fi

echo "1. Cleaning up old build..."
rm -rf lambda_build
mkdir -p lambda_build

echo "2. Copying Lambda code..."
cp lambda/*.py lambda_build/

echo "3. Installing dependencies using AWS Lambda Python 3.12 image..."
docker run --rm \
    --entrypoint "" \
    -v "$(pwd)/lambda_build":/var/task \
    -v "$(pwd)/lambda/requirements.txt":/tmp/requirements.txt \
    public.ecr.aws/lambda/python:3.12 \
    pip install -r /tmp/requirements.txt -t /var/task/ --no-cache-dir

echo "4. Cleaning up unnecessary files..."
cd lambda_build
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type f -name "*.pyo" -delete 2>/dev/null || true
cd ..

echo ""
echo "✓ Lambda package built successfully!"
echo "  Location: lambda_build/"
echo "  Size: $(du -sh lambda_build | cut -f1)"
echo ""
echo "Next step: Run 'terraform apply' to deploy"
