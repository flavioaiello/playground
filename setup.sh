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
          id: vmId
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
      
      - name: Set up Azure CLI
        uses: azure/setup-cli@v1

      - name: Login to Azure
        run: az login --service-principal -u $AZURE_SERVICE_PRINCIPAL_NAME -p ${{ secrets.AZURE_CLIENT_SECRET }} --tenant $AZURE_TENANT_ID

      - name: Deploy all Bicep files
        run: |
          for bicepFile in ./bicep/*.bicep; do
            echo "Deploying $bicepFile"
            az deployment group create --resource-group <your-resource-group> --template-file "$bicepFile"
          done
EOL

echo "GitHub Actions workflow for GitOps has been created at .github/workflows/gitops.yml"

# Add and commit changes
git add .
git commit -m "Setup GitOps configuration with Bicep files for VM deployment"

echo "Setup complete. Please push your changes to the repository."
