try{
    # We retrieve an access token from Microsoft
    $postParams = @{client_id='<insert application id>';scope='https://graph.microsoft.com/.default';client_secret='<insert secret application token>';grant_type='client_credentials'}
    $tokenResponse = Invoke-restmethod -Uri '<OAuth 2.0 token endpoint>' -Method POST -Body $postParams

    $access_token = $tokenResponse.access_token

    $getParams =  @{Authorization="Bearer $access_token";"Content-Type"="application/json";"ConsistencyLevel"="eventual"}    

    # We get the current managed devices using the Intune API
    $url = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$select=id'
    $managedDeviceIds = Invoke-webrequest -Method GET -Uri $url -Headers $getParams -ContentType 'application/json'
    $managedDeviceIds = $managedDeviceIDs | ConvertFrom-Json

    # Here we create an authorization header
    $header = @{Authorization="Bearer <256 bit token from the vpn-user-portal or admin api>"}

    # We get our local list of deployed VPN device ids
    if(Test-Path -Path "$PSScriptRoot\deployedVpnDeviceIds.txt" -PathType Leaf)
    {
        $deployedVpnDeviceIds = Get-Content -Path "$PSScriptRoot\deployedVpnDeviceIds.txt"
    }
    else{
        $deployedVpnDeviceIds = @()
    }

    # Do a fast difference check to see if managed devices are removed / added
    $removed   = [String[]][Linq.Enumerable]::Except($deployedVpnDeviceIds, $managedDeviceIds.value.id)
    $added     = [String[]][Linq.Enumerable]::Except($managedDeviceIds.value.id, $deployedVpnDeviceIds)
    
    $PSScriptRoot

    foreach ($id in $removed){
        # Ask eduVPN to remove the device and revoke its VPN configs
        $removeResponse = Invoke-WebRequest -Method Post -Uri https://vpn.strategyit.nl/vpn-user-portal/removeIntuneConfig -Headers $header -Body @{user_id="$id"}

        if($removeResponse.StatusCode -eq 200){
            $deployedVpnDeviceIds.remove($id)
        }
    }
    foreach ($id in $added){
        # Add the new managed device to eduVPN and receive a VPN config
        $addedResponse = Invoke-WebRequest -Method Post -Uri https://vpn.strategyit.nl/vpn-user-portal/deployIntuneConfig -Headers $header -Body @{profile_id = "sysvpn";user_id="$id"}

        if($addedResponse.StatusCode -eq 200){
            # Send config to Intune
            Invoke-webrequest -Method POST -Uri 'https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts' -Headers $getParams -ContentType 'application/json'
            $deployedVpnDeviceIds.Add($id)
        }
            
    }
    # Update the local list of deployed VPN device ids
    $deployedVpnDeviceIds | Out-File -FilePath "$PSScriptRoot\deployedVpnDeviceIds.txt"
    
}
catch{
$_ | Out-File -FilePath "$PSScriptRoot\eduVPN-Intune.log"
$_
}
