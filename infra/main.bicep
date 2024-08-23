resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'myResourceGroup'
  location: 'eastus'
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'myVNet'
  location: rg.location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
  }
}
