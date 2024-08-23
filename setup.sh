#!/bin/bash

# Check if GITHUB_PAT environment variable is set
if [ -z "$GITHUB_PAT" ]; then
  echo "Error: GITHUB_PAT environment variable is not set."
  echo "Please export your GitHub Personal Access Token before running this script."
  echo "Example: export GITHUB_PAT='your-github-personal-access-token'"
  exit 1
fi
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

# Set Variables
GITHUB_USERNAME="flavioaiello"
REPO_NAME="playground"
AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
AZURE_TENANT_ID=$(az account show --query tenantId --output tsv)
RESOURCE_GROUP_NAME="myResourceGroup" # Specify your desired resource group name
LOCATION="eastus" # Specify your desired Azure region
VNET_NAME="myVNet" # Specify your desired VNet name
SUBNET_NAME="mySubnet" # Specify your desired subnet name
SUBNET_PREFIX="10.0.0.0/24" # Specify your desired subnet CIDR

# Create Bicep directory if it doesn't exist
BICEP_DIR="./bicep"
if [ ! -d "$BICEP_DIR" ]; then
  echo "Creating Bicep directory at $BICEP_DIR"
  mkdir -p "$BICEP_DIR"
else
  echo "Bicep directory already exists at $BICEP_DIR"
fi

# Prompt for VM deployment parameters
read -p "Enter the VM name: " VM_NAME
read -p "Enter the admin username: " ADMIN_USERNAME
read -s -p "Enter the admin password: " ADMIN_PASSWORD
echo # Move to a new line after password input

# Create Bicep file for VM and network resources deployment
BICEP_FILE="$BICEP_DIR/vm-deployment.bicep"
if [ ! -f "$BICEP_FILE" ]; then
  echo "Creating Bicep file for VM and network resources deployment at $BICEP_FILE"
  cat <<EOL > "$BICEP_FILE"
param location string = '$LOCATION'
param vnetName string = '$VNET_NAME'
param subnetName string = '$SUBNET_NAME'
param subnetPrefix string = '$SUBNET_PREFIX'
param vmName string = '$VM_NAME'
param adminUsername string = '$ADMIN_USERNAME'
@secure()
param adminPassword string

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
        }
      }
    ]
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' = parent: vnet {
  name: subnetName
}

resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: '\${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '\${vmName}-ipconfig'
        properties: {
          subnet: {
            id: subnet.id // Reference the subnet's ID dynamically
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS2_v3' // Adjusted VM size to available SKU
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
git commit -m "Setup GitOps configuration with Bicep files including network and VM resources"

# Push changes to GitHub (ensure no sensitive files are pushed)
git push origin main

echo "Setup complete. Please add the Service Principal credentials to GitHub Secrets as AZURE_CREDENTIALS."
