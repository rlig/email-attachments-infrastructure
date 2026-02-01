#!/bin/bash
set -e

echo "======================================"
echo "Building Lambda Deployment Package"
echo "======================================"
echo ""

# Create a clean build directory
echo "1. Creating build directory..."
rm -rf lambda_build
mkdir -p lambda_build

# Copy Lambda code
echo "2. Copying Lambda code..."
cp lambda/*.py lambda_build/

# Install dependencies
echo "3. Installing Python dependencies..."
pip install -r lambda/requirements.txt -t lambda_build/ --quiet

# Remove unnecessary files to reduce package size
echo "4. Cleaning up unnecessary files..."
cd lambda_build
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type f -name "*.pyo" -delete 2>/dev/null || true
cd ..

echo "✓ Lambda package built successfully in lambda_build/"
echo ""
echo "Package contents:"
ls -lh lambda_build/

echo ""
echo "Next step: Run 'terraform apply' to deploy the updated Lambda function"
