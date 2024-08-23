param actionGroups_AGManager_name string
param actionGroups_AGOwner_name string
param workspaces_DefaultEASM_name string

resource workspaces_DefaultEASM_name_resource 'Microsoft.Easm/workspaces@2023-04-01-preview' = {
  location: 'eastus'
  name: workspaces_DefaultEASM_name
  properties: {}
}

resource actionGroups_AGManager_name_resource 'microsoft.insights/actionGroups@2023-09-01-preview' = {
  location: 'Global'
  name: actionGroups_AGManager_name
  properties: {
    armRoleReceivers: [
      {
        name: 'EmailRBACOwner'
        roleId: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
        useCommonAlertSchema: true
      }
    ]
    automationRunbookReceivers: []
    azureAppPushReceivers: []
    azureFunctionReceivers: []
    emailReceivers: [
      {
        emailAddress: 'flavioaiello@microsoft.com'
        name: 'EmailOwner'
        useCommonAlertSchema: true
      }
      {
        emailAddress: 'camarche@microsoft.com'
        name: 'EmailManager'
        useCommonAlertSchema: true
      }
    ]
    enabled: true
    eventHubReceivers: []
    groupShortName: actionGroups_AGManager_name
    itsmReceivers: []
    logicAppReceivers: []
    smsReceivers: []
    voiceReceivers: []
    webhookReceivers: []
  }
}

resource actionGroups_AGOwner_name_resource 'microsoft.insights/actionGroups@2023-09-01-preview' = {
  location: 'Global'
  name: actionGroups_AGOwner_name
  properties: {
    armRoleReceivers: [
      {
        name: 'EmailRBACOwner'
        roleId: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
        useCommonAlertSchema: true
      }
    ]
    automationRunbookReceivers: []
    azureAppPushReceivers: []
    azureFunctionReceivers: []
    emailReceivers: [
      {
        emailAddress: 'flavioaiello@microsoft.com'
        name: 'EmailOwner'
        useCommonAlertSchema: true
      }
    ]
    enabled: true
    eventHubReceivers: []
    groupShortName: actionGroups_AGOwner_name
    itsmReceivers: []
    logicAppReceivers: []
    smsReceivers: []
    voiceReceivers: []
    webhookReceivers: []
  }
}
