#!/bin/bash
set -e

# Generate CloudFront signing keys
echo "Generating CloudFront RSA key pair..."

# Create keys directory
mkdir -p keys

# Generate RSA private key (2048-bit)
openssl genrsa -out keys/private_key.pem 2048

# Generate public key from private key
openssl rsa -pubout -in keys/private_key.pem -out keys/public_key.pem

echo "✓ Keys generated successfully:"
echo "  - keys/private_key.pem (keep secure!)"
echo "  - keys/public_key.pem"
echo ""
echo "⚠️  IMPORTANT: Keep private_key.pem secure and never commit to Git!"
echo "Add keys/ to .gitignore"

# Add to .gitignore
if [ ! -f .gitignore ]; then
    echo "keys/" > .gitignore
    echo "*.tfvars" >> .gitignore
    echo ".terraform/" >> .gitignore
    echo "*.tfstate" >> .gitignore
    echo "*.tfstate.backup" >> .gitignore
    echo "lambda_package.zip" >> .gitignore
else
    if ! grep -q "keys/" .gitignore; then
        echo "keys/" >> .gitignore
    fi
fi

echo "✓ .gitignore updated"
