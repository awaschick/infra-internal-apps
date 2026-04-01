#!/bin/bash

source "$(dirname "$0")/common.sh"

# Set the virtual environment name
VENV_DIR="${base_path}/.venv"

# Check if the virtual environment already exists
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating virtual environment..."
  ${python_executable} -m venv "$VENV_DIR"
else
    echo "Virtual environment already exists."
fi

# Activate the virtual environment
source "$VENV_DIR/bin/activate"

# Get latest Terraform version and download link
TERRAFORM_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version')
DOWNLOAD_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${terraform_platform}.zip"

# Create a temporary directory for the Terraform download
TEMP_DIR=$(mktemp -d)
echo "Downloading Terraform from ${DOWNLOAD_URL}..."
curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/terraform.zip"

# Unzip Terraform
echo "Extracting Terraform..."
unzip "$TEMP_DIR/terraform.zip" -d "$TEMP_DIR"

# Move Terraform executable to the virtual environment's bin directory
echo "Moving Terraform to virtual environment bin..."
mv "$TEMP_DIR/terraform" "$VENV_DIR/bin"

# Clean up temporary directory
rm -rf "$TEMP_DIR"

# Inform the user that Terraform is ready
echo "Terraform installed in virtual environment."

# Verify Terraform installation
echo "Checking Terraform version..."
source ./.venv/bin/activate
terraform --version
