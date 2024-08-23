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
AZURE_SERVICE_PRINCIPAL_NAME="my-github-actions-sp"
RESOURCE_GROUP_NAME="myResourceGroup" # Specify your desired resource group name
LOCATION="eastus" # Specify your desired Azure region

# Create Service Principal
# echo "Creating Azure Service Principal..."
# SERVICE_PRINCIPAL_JSON=$(az ad sp create-for-rbac --name "$AZURE_SERVICE_PRINCIPAL_NAME" --role Contributor --scopes "/subscriptions/$AZURE_SUBSCRIPTION_ID" --sdk-auth)

if [ $? -ne 0 ]; then
  echo "Failed to create Service Principal."
  exit 1
fi

# Output the Service Principal credentials for manual addition to GitHub Secrets
# echo "Service Principal credentials (add these to GitHub Secrets as AZURE_CREDENTIALS):"
# echo "$SERVICE_PRINCIPAL_JSON"

# Create the Resource Group if it doesn't exist
echo "Checking if resource group '$RESOURCE_GROUP_NAME' exists..."
if ! az group show --name "$RESOURCE_GROUP_NAME" > /dev/null 2>&1; then
  echo "Resource group '$RESOURCE_GROUP_NAME' does not exist. Creating it now..."
  az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"
else
  echo "Resource group '$RESOURCE_GROUP_NAME' already exists."
fi

# Create Bicep directory if it doesn't exist
BICEP_DIR="./bicep"
if [ ! -d "$BICEP_DIR" ]; then
  echo "Creating Bicep directory at $BICEP_DIR"
  mkdir -p "$BICEP_DIR"
else
  echo "Bicep directory already exists at $BICEP_DIR"
fi

# Create Bicep file for VM deployment
BICEP_FILE="$BICEP_DIR/vm-deployment.bicep"
if [ ! -f "$BICEP_FILE" ]; then
  echo "Creating Bicep file for VM deployment at $BICEP_FILE"
  cat <<EOL > "$BICEP_FILE"
param vmName string
param adminUsername string
@secure()
param adminPassword string
param location string = resourceGroup().location

resource vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${vmName}-ipconfig'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}
EOL
else
  echo "Bicep file for VM deployment already exists at $BICEP_FILE"
fi

# Initialize Git repository if not already initialized
if [ ! -d ".git" ]; then
  echo "Initializing a new Git repository."
  git init
  git remote add origin "https://github.com/$GITHUB_USERNAME/$REPO_NAME.git"
else
  echo "Git repository already initialized."
fi

# Configure GitHub Actions for GitOps
echo "Configuring GitHub Actions for GitOps..."
cat <<EOL > .github/workflows/gitops.yml
name: GitOps Workflow

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v2
      
      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: \${{ secrets.AZURE_CREDENTIALS }}

      - name: Deploy all Bicep files
        uses: azure/cli@v2
        with:
          azcliversion: latest
          inlineScript: |
            for bicepFile in ./bicep/*.bicep; do
              echo "Deploying \$bicepFile"
              az deployment group create --resource-group "$RESOURCE_GROUP_NAME" --template-file "\$bicepFile"
            done
EOL

echo "GitHub Actions workflow for GitOps has been created at .github/workflows/gitops.yml"

# Add and commit changes
git add .
git commit -m "Setup GitOps configuration with Bicep files"

# Push changes to GitHub (ensure no sensitive files are pushed)
git push origin main

echo "Setup complete. Please add the Service Principal credentials to GitHub Secrets as AZURE_CREDENTIALS."
