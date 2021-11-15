Write-Output "Initialized, Connecting...." 
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

   # "Logging in to Azure..."
    Connect-AzAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
#Write-Output "Connected...."
function RegenerateKey($keyId, $providerAddress){
    Write-Output "Regenerating key. Id: $keyId Resource Id: $providerAddress"
    $storageAccountName = ($providerAddress -split '/')[8]
    $resourceGroupName = ($providerAddress -split '/')[4]
    #Regenerate key 
    New-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName -KeyName $keyId
    $newKeyValue = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName|where KeyName -eq $keyId).value
    return $newKeyValue
}

function AddSecretToKeyVault($keyVAultName,$secretName,$newAccessKeyValue,$exprityDate,$tags){
    $secretvalue = ConvertTo-SecureString "$newAccessKeyValue" -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $keyVAultName -Name $secretName -SecretValue $secretvalue -Tag $tags -Expires $expiryDate
}

function GetAlternateCredentialId($keyId){
    $validCredentialIdsRegEx = 'key[1-2]'
    If($keyId -NotMatch $validCredentialIdsRegEx){
        throw "Invalid credential id: $keyId. Credential id must follow this pattern:$validCredentialIdsRegEx"
    }
    If($keyId -eq 'key1'){
        return "key2"
    }
    Else{
        return "key1"
    }
}

function AddKeyValueToDB($keyName,$keyValue, $keyVaultName){
   #Add-Type -AssemblyName "Microsoft.SqlServer.Smo,Version=21.1.18256,Culture=neutral,PublicKeyToken=89845dcd8080cc91"
   $DBConnection = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name 'DBConnection' -AsPlainText
   $sqlConn = New-Object System.Data.SqlClient.SqlConnection
   $sqlConn.ConnectionString = $DBConnection
   $sqlConn.Open()
   $sqlcmd = $sqlConn.CreateCommand()
   $sqlcmd = New-Object System.Data.SqlClient.SqlCommand
   $sqlcmd.Connection = $sqlConn
   $query = "insert into [dbo].[KeyVaultHistory](KeyName,KeyValue) values('$keyName','$keyValue')"
   $sqlcmd.CommandText = $query
   $sqlcmd.ExecuteNonQuery()
   $sqlConn.Close()
   Write-Output "DB Insertion Completed"
}

function AddKeyValueToDB_MI($keyName,$keyValue){
   #Add-Type -AssemblyName "Microsoft.SqlServer.Smo,Version=21.1.18256,Culture=neutral,PublicKeyToken=89845dcd8080cc91"
   $resourceURI = "https://database.windows.net/"
   $tokenAuthURI = "https://127.0.0.1:41056/MSI/token/?resource=$resourceURI&api-version=2017-09-01"
   $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="8304eed9-533a-4abf-865a-ff936fe2c29f"} -Uri $tokenAuthURI
   $accessToken = $tokenResponse.access_token
   $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
   $SqlServerName = "tpeci-dbserver"
   $SqlDBName = "tpeciSQLDB"
   $SqlConnection.ConnectionString = "Data Source =$SqlServerName.database.windows.net ; Initial Catalog = $SqlDBName"
   $SqlConnection.AccessToken = $accessToken
   $SqlConnection.Open()
   $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
   $query = "insert into [dbo].[KeyVaultHistory](KeyName,KeyValue) values('$keyName','$keyValue')"
   $SqlCmd.CommandText =  $query
   $SqlCmd.Connection = $SqlConnection
   $SqlCmd.ExecuteNonQuery()
   $SqlConnection.Close()
   Write-Output "MI-DB Insertion Completed"
}
function RoatateSecret($keyVaultName,$secretName){
    #Retrieve Secret
    $secret = (Get-AzKeyVaultSecret -VaultName $keyVAultName -Name $secretName) 
    #Retrieve Secret Info
    $validityPeriodDays = $secret.Tags["ValidityPeriodDays"]
    $credentialId=  $secret.Tags["CredentialId"]
    $providerAddress = $secret.Tags["ProviderAddress"]
    
    Write-Output "Secret Info Retrieved"
    Write-Output "Validity Period: $validityPeriodDays"
    Write-Output "Credential Id: $credentialId"
    Write-Output "Provider Address: $providerAddress"

    #Get Credential Id to rotate - alternate credential
    $alternateCredentialId = GetAlternateCredentialId $credentialId
    Write-Output "Alternate credential id: $alternateCredentialId"

    #Regenerate alternate access key in provider
    $newAccessKeyValue = (RegenerateKey $alternateCredentialId $providerAddress)[-1]
    Write-Output "Access key regenerated. Access Key Id: $alternateCredentialId Resource Id: $providerAddress"

    #Add new access key to Key Vault
    $newSecretVersionTags = @{}
    $newSecretVersionTags.ValidityPeriodDays = $validityPeriodDays
    $newSecretVersionTags.CredentialId=$alternateCredentialId
    $newSecretVersionTags.ProviderAddress = $providerAddress

    $expiryDate = (Get-Date).AddDays([int]$validityPeriodDays).ToUniversalTime()
    AddSecretToKeyVault $keyVAultName $secretName $newAccessKeyValue $expiryDate $newSecretVersionTags
    Write-Output "New access key added to Key Vault. Secret Name: $secretName"
    AddKeyValueToDB $secretName $newAccessKeyValue $keyVaultName
}
RoatateSecret 'tpeci-kv-lab' 'storageAccessKey'
