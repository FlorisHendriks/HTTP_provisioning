try{
    # We retrieve an access token from Microsoft
    $postParams = @{client_id='6ce7fc35-55d3-4779-b422-04580130b55d';scope='https://graph.microsoft.com/.default';client_secret='client_secret_placeholder';grant_type='client_credentials'}
    $tokenResponse = Invoke-restmethod -Uri https://login.microsoftonline.com/a9d8059a-38d4-4690-bdd4-9f7d0662d8d0/oauth2/v2.0/token -Method POST -Body $postParams

    $access_token = $tokenResponse.access_token

    $getParams =  @{Authorization="Bearer $access_token";"Content-Type"="application/json";"ConsistencyLevel"="eventual"}    

    $devicemanagementParams =  @{Authorization="Bearer $access_token"}

    $acceptHeader = @{Authorization="Bearer $access_token"; Accept="application/json"}

    # We get the current managed devices using the Intune API
    $url = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$select=id'
    $managedDeviceIds = Invoke-webrequest -usebasicparsing -Method GET -Uri $url -Headers $getParams -ContentType 'application/json'
    $managedDeviceIds = $managedDeviceIDs | ConvertFrom-Json

    # We get our local list of deployed VPN device ids
    if(Test-Path -Path "$PSScriptRoot\deployedVpnDeviceIds.txt" -PathType Leaf)
    {
        $deployedVpnDeviceIds = Get-Content -Path "$PSScriptRoot\deployedVpnDeviceIds.txt"
    }
    else{
        $deployedVpnDeviceIds = @()
    }
    
    # Do a fast difference check to see if managed devices are removed / added
    $removed = [String[]][Linq.Enumerable]::Except([String[]]$deployedVpnDeviceIds, [String[]]$managedDeviceIds.value.id)
    $added = [String[]][Linq.Enumerable]::Except([String[]]$managedDeviceIds.value.id, [String[]]$deployedVpnDeviceIds)

    # Remove and revoke the deleted managed devices from eduVPN
    foreach ($id in $removed){
        $removeResponse = Invoke-WebRequest -usebasicparsing -Method Post -Uri 'https://vpn.strategyit.nl/vpn-user-portal/api/v3/removeIntuneConfig?token=256bit_secret_token' -Headers $header -Body @{user_id="$id"}
		
        if($removeResponse.StatusCode -eq 200){
            $deployedVpnDeviceIds = @($deployedVpnDeviceIds | Where-Object { $_ -ne $id })
            echo "$id removed"
        }
    }
    foreach ($id in $added){
        $temp = @($id)
        $deployedVpnDeviceI = $deployedVpnDeviceI + $temp
        echo "$id added"
    }
    $deployedVpnDeviceI | Out-File "$PSScriptRoot\deployedVpnDeviceIds.txt"
}
catch{
$_ | Out-File -FilePath "$PSScriptRoot\eduVPN-Intune.log"
$_
}
