# rotatestorageKey_powershell
The Automation Script is used to rotate storage account access key, using powershell script which is executed using Azure Automation Account.
For the script to work you have to create a azure automation account with "AzureRunAsConnection"
The purpose of the script is to update the storage access key which get regenerated in every 60-90 days by the storage account. The script is scheduled to run before expiry of the 
storage access key. It will regenerate the access key, update the same into the keyvault and also if needed then the same key can be updated into the DB so that it could be used
for other purpose.

Steps
1. Create a storage account
2. Create a key vault
3. Add secret to keyvault which stores the accesskey, also add the Tag with below details.
   CredentialId = key2
   ValidityPeriodDays = 60
   ProviderAddress = /subscriptions/{subscription_ID}/resourceGroups/{ResourceGroup_Name}/providers/Microsoft.Storage/storageAccounts/{StorageAccount_Name}
4. you can also get the ProviderAddress by running below command in powershell, by logging into your azure account. it is available as ID property.
   Get-AzStorageAccount -Name {StorageAccount_Name} -ResourceGroupName {ResourceGroup_Name} | Select-Object -Property *
5. Also create a secret in keyvault which will store the DBConnection string. Get the DBConnection string from SQL Server and add here, so that it will be used to store the access
   key in DB
6. Then Create a Azure Automation Account and add this as runbook.
7. https://docs.microsoft.com/en-us/azure/key-vault/secrets/tutorial-rotation-dual?tabs=azurepowershell 
