# Handle command-line arguments
param (
    [string]$s,
    [string]$p,
    [string]$t
 )
if(-not($s) -or -not($p) -or -not($t))
{
	Throw 'You did not (fully) specify the parameters -s, -p and -t'
}
"try{
    # Get managed device id
    `$id = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot\EstablishedCorrelations' -Name EntDMID

    # Get VPN config and install the tunnel
    `$Response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri `"https://$s/vpn-user-portal/api/v3/deployIntuneConfig?token=$t`" -Body @{profile_id = `"$p`";user_id=`"`$id`"}
    
    if(`$Response.StatusCode -eq 200)
    { 
        # Install and deploy WireGuard tunnel if we received a wireguard-configuration
        if(`$Response.RawContent.Contains(`"wireguard-profile`"))
        {
            Invoke-WebRequest https://download.wireguard.com/windows-client/wireguard-amd64-0.5.3.msi -OutFile `"WireGuard.msi`"
            Start-Process msiexec.exe -ArgumentList '/q', '/n', '/I', 'WireGuard.msi' -Wait -NoNewWindow -PassThru | Out-Null
            [System.Text.Encoding]::UTF8.GetString(`$Response.Content) | Out-File -FilePath `"C:\Program Files\WireGuard\Data\wg0.conf`"
            Start-Process -FilePath `"C:\Windows\System32\cmd.exe`" -verb runas -ArgumentList {/c `"`"C:\Program Files\WireGuard\wireguard.exe`" /installtunnelservice `"C:\Program Files\WireGuard\Data\wg0.conf`"`"}
        }
        # else install and deploy OpenVPN
        else
        {
            Invoke-WebRequest https://swupdate.openvpn.org/community/releases/OpenVPN-2.5.7-I602-amd64.msi -OutFile `"OpenVPN.msi`"
            Start-Process msiexec.exe -ArgumentList '/q', '/n', '/I', 'OpenVPN.msi', 'ADDLOCAL=OpenVPN.Service,OpenVPN,Drivers.TAPWindows6,Drivers' -Wait -NoNewWindow -PassThru | Out-Null
            [System.Text.Encoding]::UTF8.GetString(`$Response.Content) | Out-File -Encoding `"UTF8`" -FilePath `"C:\Program Files\OpenVPN\config-auto\openvpn.ovpn`"
        }
    }
    else
    {
        throw `"We received statuscode `$Response.StatusCode from the eduVPN server, we expected 200`"
    }
}
catch{
`$_ | Out-File -FilePath `"C:\eduVPN_Intune_Deployment.log`"
}" | Out-File -Encoding "UTF8" `"UTF -FilePath "$PSScriptRoot\Intune_management_script.ps1"
echo "$PSScriptRoot\Intune_management_script.ps1 has been created"
