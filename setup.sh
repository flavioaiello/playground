#!/bin/bash

# Check if GITHUB_PAT environment variable is set
if [ -z "$GITHUB_PAT" ]; then
  echo "Error: GITHUB_PAT environment variable is not set."
  echo "Please export your GitHub Personal Access Token before running this script."
  echo "Example: export GITHUB_PAT='your-github-personal-access-token'"
  exit 1
fi

# Set Variables
GITHUB_USERNAME="flavioaiello"
REPO_NAME="playground"
AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
AZURE_TENANT_ID=$(az account show --query tenantId --output tsv)
AZURE_SERVICE_PRINCIPAL_NAME="github-actions-sp"

# Check if required tools are installed
for tool in az jq git curl openssl base64; do
  if ! command -v $tool &> /dev/null; then
    echo "$tool could not be found, please install it before running the script."
    exit 1
  fi
done

# Ensure Azure CLI is logged in
if ! az account show &> /dev/null; then
  echo "Please log in to Azure CLI using 'az login' before running the script."
  exit 1
fi

# Get the list of unique resource groups from all resources
RESOURCE_GROUPS=$(az resource list --query "[].resourceGroup" -o tsv | sort -u)

# Iterate over each resource group
for RESOURCE_GROUP in $RESOURCE_GROUPS; do
  echo "Processing resource group: $RESOURCE_GROUP"

  BICEP_DIR="infra/$RESOURCE_GROUP"
  mkdir -p $BICEP_DIR

  # Export the entire resource group as an ARM template
  echo "Exporting ARM template for resource group: $RESOURCE_GROUP"
  az group export --name $RESOURCE_GROUP --output json > $BICEP_DIR/exported-template.json

  if [[ $? -ne 0 || ! -s $BICEP_DIR/exported-template.json ]]; then
    echo "Failed to export ARM template or file is empty for resource group $RESOURCE_GROUP. Skipping..."
    continue
  fi

  # Convert ARM template to Bicep
  echo "Converting ARM template to Bicep for resource group $RESOURCE_GROUP..."
  az bicep decompile --file $BICEP_DIR/exported-template.json > $BICEP_DIR/main.bicep

  if [[ $? -ne 0 || ! -s $BICEP_DIR/main.bicep ]]; then
    echo "Failed to convert ARM template to Bicep or file is empty for resource group $RESOURCE_GROUP. Skipping..."
    continue
  fi
done

# Initialize Git repository and push to GitHub
echo "Committing Bicep files..."
git add .
git commit -m "Initial commit with Bicep files for all resource groups"
git pull origin main --rebase
git push origin main

# Create Azure Service Principal for GitHub Actions
echo "Creating Azure Service Principal..."
AZURE_SP=$(az ad sp create-for-rbac --name $AZURE_SERVICE_PRINCIPAL_NAME --role contributor --scopes /subscriptions/$AZURE_SUBSCRIPTION_ID --query "{clientId: appId, clientSecret: password, tenantId: tenant, subscriptionId: subscriptionId}" --output json)

# Get GitHub Repository Public Key
public_key_response=$(curl -u $GITHUB_USERNAME:$GITHUB_PAT -X GET https://api.github.com/repos/$GITHUB_USERNAME/$REPO_NAME/actions/secrets/public-key)
PUBLIC_KEY=$(echo $public_key_response | jq -r .key)
KEY_ID=$(echo $public_key_response | jq -r .key_id)

if [[ -z "$PUBLIC_KEY" || -z "$KEY_ID" ]]; then
  echo "Error retrieving public key for GitHub repository."
  exit 1
fi

# Encrypt the secret using the public key with pkeyutl
echo -n $AZURE_SP | openssl pkeyutl -encrypt -pubin -inkey <(echo $PUBLIC_KEY | base64 -d) -out encrypted-value.bin
ENCRYPTED_VALUE=$(base64 < encrypted-value.bin)

# Upload the secret to GitHub
curl -u $GITHUB_USERNAME:$GITHUB_PAT -X PUT https://api.github.com/repos/$GITHUB_USERNAME/$REPO_NAME/actions/secrets/AZURE_CREDENTIALS \
    -d "{\"encrypted_value\":\"$ENCRYPTED_VALUE\",\"key_id\":\"$KEY_ID\"}"

# Create GitHub Actions workflow file
echo "Creating GitHub Actions workflow..."
mkdir -p .github/workflows
cat <<'GITHUB_ACTIONS' > .github/workflows/deploy.yml
name: Deploy Azure Infrastructure

on:
  push:
    branches:
      - main

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v3  # Updated to the latest version

    - name: Set up Azure CLI
      uses: azure/CLI@v2  # Updated to the latest version

    - name: Login to Azure
      uses: azure/login@v2  # Updated to the latest version
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}

    - name: Deploy Bicep file
      run: |
        for dir in infra/*; do
          az deployment group create \
            --resource-group $(basename $dir) \
            --template-file $dir/main.bicep
        done
GITHUB_ACTIONS

# Commit and push the GitHub Actions workflow
echo "Committing GitHub Actions workflow..."
git add .github/workflows/deploy.yml
git commit -m "Add GitHub Actions workflow for Bicep deployment of all resource groups"
git push origin main

echo "Setup complete. Your infrastructure will deploy automatically on pushes to the main branch."
