# Handle command-line arguments
param (
    [string]$s,
    [string]$id,
    [string]$cs,
    [string]$t,
    [string]$e
 )
if(!($s -and $id -and $cs -and $t -and $e))
{
	Throw 'You did not (fully) specify the parameters -s, -id, -cs, -t, and -e' 
}
"try{
    # We retrieve an access token from Microsoft
    `$postParams = @{client_id='$id';scope='https://graph.microsoft.com/.default';client_secret='$cs';grant_type='client_credentials'}
    `$tokenResponse = Invoke-restmethod -Uri '$e' -Method POST -Body `$postParams

    `$access_token = `$tokenResponse.access_token

    `$getParams =  @{Authorization=`"Bearer `$access_token`";'Content-Type'='application/json';'ConsistencyLevel'='eventual'}    

    `$devicemanagementParams =  @{Authorization=`"Bearer `$access_token`"}

    `$acceptHeader = @{Authorization=`"Bearer `$access_token`"; Accept='application/json'}

    # We get the current managed devices using the Intune API
    `$url = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id'
    `$managedDeviceIds = Invoke-webrequest -usebasicparsing -Method GET -Uri `$url -Headers `$getParams -ContentType 'application/json'
    `$managedDeviceIds = `$managedDeviceIDs | ConvertFrom-Json

    # We get our local list of deployed VPN device ids
    if(Test-Path -Path `"$PSScriptRoot\deployedVpnDeviceIds.txt`" -PathType Leaf)
    {
        `$deployedVpnDeviceIds = Get-Content -Path `"`$PSScriptRoot\deployedVpnDeviceIds.txt`"
    }
    if(`$deployedVpnDeviceIds -eq `$null)
    {
        `$deployedVpnDeviceIds = @()
    }
    # Do a fast difference check to see if managed devices are removed / added
    if(`$managedDeviceIds.'@odata.count' -ne 0){
        `$removed = [String[]][Linq.Enumerable]::Except([String[]]`$deployedVpnDeviceIds, [String[]]`$managedDeviceIds.value.id)
        `$added = [String[]][Linq.Enumerable]::Except([String[]]`$managedDeviceIds.value.id, [String[]]`$deployedVpnDeviceIds)
    }
    else{
        `$removed = [String[]][Linq.Enumerable]::Except([String[]]`$deployedVpnDeviceIds, [String[]]`$managedDeviceIds.value)
        `$added = [String[]][Linq.Enumerable]::Except([String[]]`$managedDeviceIds.value, [String[]]`$deployedVpnDeviceIds)
    }

    # Remove and revoke the deleted managed devices from eduVPN
    foreach (`$id in `$removed){
        `$removeResponse = Invoke-WebRequest -usebasicparsing -Method Post -Uri 'https://$s/vpn-user-portal/api/v3/removeIntuneConfig?token=256bit_token_placeholder' -Headers `$header -Body @{user_id='`$id'}
        if(`$removeResponse.StatusCode -eq 200){
            `$deployedVpnDeviceIds = @(`$deployedVpnDeviceIds | Where-Object { `$_ -ne `$id })
        }
    }
    foreach (`$id in `$added){
        `$temp = @(`$id)
        `$deployedVpnDeviceIds = `$deployedVpnDeviceIds + `$temp
    }
    `$deployedVpnDeviceIds | Out-File `"`$PSScriptRoot\deployedVpnDeviceIds.txt`"
}
catch{
`$_ | Out-File -FilePath `"`$PSScriptRoot\eduVPN-Intune.log`"
}" | Out-File -Encoding "UTF8" -FilePath "$PSScriptRoot\Powershell_Daemon.ps1"

# Create a scheduled task that runs the Powershell_Daemon.ps1 every 5 minutes
schtasks.exe /create /tn "eduVPN Powershell Daemon" /tr "powershell.exe $PSScriptRoot\Powershell_Daemon.ps1" /sc minute /mo 5 /ru "System"

echo "The Powershell Daemon has been deployed"
