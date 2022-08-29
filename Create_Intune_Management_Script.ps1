# Handle command-line arguments
param (
    [string]$s,
    [string]$p
 )
if(-not($s) -or -not($p))
{
	Throw 'You did not (fully) specify the parameters -s, -p and -t'
}
"try{
    # Get managed device id
    `$DeviceID = Get-ItemPropertyValue HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot\EstablishedCorrelations -Name EntDMID

    # Get the certificate from either the system user store or the local machine, depends on how you enroll the device. 
    `$certStorePath  = 'Cert:\CurrentUser\My'
    `$MachineCertificate = Get-ChildItem -Path `$certStorePath | Where-Object {`$_.Subject -like `"*`$DeviceID*`"}


    if(`$MachineCertificate -eq `$null)
    {
        `$certStorePath  = 'Cert:\LocalMachine\My'
        `$MachineCertificate = Get-ChildItem -Path `$certStorePath | Where-Object {`$_.Subject -like `"*`$DeviceID*`"}
    }

    if(`$MachineCertificate -eq `$null)
    {
        Throw 'We did not find a certificate, is the device enrolled?'
    }

    # Get VPN config and install the tunnel
    `$Response = Invoke-WebRequest -Method 'Post' -Uri 'https://$s' -UseBasicParsing -Certificate `$MachineCertificate -Body @{profile_id = `"$p`";user_id=`"`$DeviceID`"}
    
    if(`$Response.StatusCode -eq 200)
    {
    
        # Using winget as system user is quite a hassle (https://github.com/microsoft/winget-cli/issues/548). 
        # It can not find the winget path by itself so we need to resolve the path 
        # (https://call4cloud.nl/2021/05/cloudy-with-a-chance-of-winget/#part3):
     
        `$ResolveWingetPath = Resolve-Path `"C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe`"
        if (`$ResolveWingetPath){
           `$WingetPath = `$ResolveWingetPath[-1].Path
        }
        else{
            Throw `"Winget not found`"
        }
        cd `$WingetPath

        # Install and deploy WireGuard tunnel if we received a wireguard-configuration
        if(`$Response.RawContent.Contains(`"[Interface]`"))
        {
            .\winget.exe install --silent WireGuard.WireGuard --accept-package-agreements --accept-source-agreements
            $Response.Content | Out-File -FilePath `"C:\Program Files\WireGuard\Data\wg0.conf`"
            Start-Process -FilePath `"C:\Windows\System32\cmd.exe`" -verb runas -ArgumentList {/c `"`"C:\Program Files\WireGuard\wireguard.exe`" /installtunnelservice `"C:\Program Files\WireGuard\Data\wg0.conf`"`"}
        }
        # else install and deploy OpenVPN
        else
        {
            .\winget.exe install OpenVPNTechnologies.OpenVPN --silent --accept-package-agreements --accept-source-agreements --override `"ADDLOCAL=OpenVPN.Service,OpenVPN,Drivers.TAPWindows6,Drivers`"
            Start-Process msiexec.exe -ArgumentList '/q', '/n', '/I', 'OpenVPN.msi', 'ADDLOCAL=OpenVPN.Service,OpenVPN,Drivers.TAPWindows6,Drivers' -Wait -NoNewWindow -PassThru | Out-Null
            [System.Text.Encoding]::UTF8.GetString(`$Response.Content) | Out-File -Encoding `"UTF8`" -FilePath `"C:\Program Files\OpenVPN\config-auto\openvpn.ovpn`"
        }
    }
    else
    {
        Throw `"We received statuscode `$Response.StatusCode from the eduVPN server, we expected 200`"
    }
}
catch{
`$_ | Out-File -FilePath `"$PSScriptRoot\eduVpnDeployment.log`"
}" | Out-File -Encoding "UTF8" -FilePath "$PSScriptRoot\Windows_Intune_management_script.ps1"

echo "$PSScriptRoot\Windows_Intune_management_script.ps1 has been created"

"#!/bin/sh
# Catch errors and log it to /Library/Logs/Microsoft/eduVpnDeployment.log
set -e
trap 'catch `$? `$LINENO' EXIT
catch() {
	if [ `"`$1`" != `"0`" ]; then
     		echo `"Error `$1 occurred on `$2`" > /Library/Logs/Microsoft/eduVpnDeployment.log 
   	fi
}
# Get the managed device id
id=`$(security find-certificate -a | awk -F= '/issu/ && /MICROSOFT INTUNE MDM DEVICE CA/ { getline; print `$2 }')
# Retrieve config from eduVPN
response=`$(curl -o - -i -s -X POST `"https://$s/vpn-user-portal/api/v3/deployIntuneConfig?token=$t`" -d `"profile_id=$p&user_id=`$id`")
http_status=`$(echo `"`$response`" | awk 'NR==1 {print `$2}')
if [ `$http_status == `"200`" ]; then
	# Install the latest Macports version, which is a package manager for macOS
	
	version=`$( curl -fs --url 'https://raw.githubusercontent.com/macports/macports-base/master/config/RELEASE_URL' )
	version=`${version##*/v}
    	curl -L -O --url `"https://github.com/macports/macports-base/releases/download/v`${version}/MacPorts-`${version}.tar.gz`"
	tar -zxf   MacPorts-`${version}.tar.gz 2>/dev/null
	cd MacPorts-`${version}
	CC=/usr/bin/cc ./configure \
     	--prefix=/opt/local \
     	--with-install-user=root \
     	--with-install-group=admin \
     	--with-directory-mode=0755 \
     	--enable-readline \
	&& make SELFUPDATING=1 \
	&& make install SELFUPDATING=1
	# update MacPorts itself
	/opt/local/bin/port -dN selfupdate
	
	# cleanup
	cd ..
	rm  -rf  ./MacPorts-`${version}	
	# Install and deploy WireGuard tunnel if we received a wireguard-configuration
	vpnProtocol=`$(echo `"`$response`" | awk -F':' '/Content-Type/ {print `$2}')
	vpnProtocol=`"`$(echo `"`$vpnProtocol`" | tr -d '[:space:]')`"
	if [ `"`$vpnProtocol`" == `"application/x-wireguard-profile`" ]; then
		echo `"wireguard`"
		#su floris -c `"/Users/floris/Downloads/homebrew/bin/brew install wireguard-tools`"
		if [ ! -e /etc/wireguard ]; then
			mkdir -m 600 /etc/wireguard/
		fi
		echo `"`$response`" | perl -ne 'print unless 1.../^\s`$/' > /etc/wireguard/wg0.conf
		port -N install wireguard-tools
		# Create a wireguard daemon
		echo `"<?xml version=`"1.0`" encoding=`"UTF-8`"?>
		<!DOCTYPE plist PUBLIC `"-//Apple Computer//DTD PLIST 1.0//EN`" `"http://www.apple.com/DTDs/PropertyList-1.0.dtd`">
		<plist version=`"1.0`">
		<dict>
		<key>StandardOutPath</key>
                <string>/var/logs/WireguardDaemonOutput.log</string>
                <key>StandardErrorPath</key>
                <string>/var/logs/WireguardDaemonError.log</string>
  		<key>Label</key>
  		<string>com.wireguard.wg0</string>
  		<key>ProgramArguments</key>
  		<array>
    			<string>/opt/local/bin/wg-quick</string>
    			<string>up</string>
    			<string>/etc/wireguard/wg0.conf</string>
  		</array>
  		<key>KeepAlive</key>
  		<false/>
  		<key>RunAtLoad</key>
  		<true/>
  		<key>TimeOut</key>
  		<integer>90</integer>
		<key>EnvironmentVariables</key>
                <dict>
                <key>PATH</key>
                <string>/opt/local/bin</string>
                </dict>
		</dict>
		</plist>`" > /Library/LaunchDaemons/wireguard.plist
		# Change the permissions of the openvpn launch daemon
        	chown root:wheel /Library/LaunchDaemons/wireguard.plist
        	# Load and execute the LaunchDaemon
        	launchctl load /Library/LaunchDaemons/wireguard.plist
	else
		# We received an openVPN config
		if [ ! -e /etc/openvpn ]; then
			mkdir -m 600 /etc/openvpn/
		fi
		echo `"`$response`" | perl -ne 'print unless 1.../^\s`$/' > /etc/openvpn/openvpn.ovpn
		port -N install openvpn3
	
		echo `"<?xml version='1.0' encoding='UTF-8'?>
		<!DOCTYPE plist PUBLIC `"-//Apple//DTD PLIST 1.0//EN`"
		`"http://www.apple.com/DTDs/PropertyList-1.0.dtd`" >
		<plist version='1.0'>
		<dict>
		<key>StandardOutPath</key>
		<string>/var/logs/startVPNoutput.log</string>
		<key>StandardErrorPath</key>
		<string>/var/logs/startVPNerror.log</string>
		<key>Label</key><string>eduvpn.openvpn</string>
		<key>ProgramArguments</key>
		<array>
			<string>/opt/local/bin/ovpncli</string>
			<string>--config</string>
			<string>/etc/openvpn/openvpn.ovpn</string>
		</array>
		<key>KeepAlive</key><false/>
		<key>RunAtLoad</key><true/>
		<key>TimeOut</key>
                <integer>90</integer>
		</dict>
		</plist>`" > /Library/LaunchDaemons/openvpn.plist
	# Change the permissions of the openvpn launch daemon
	chown root:wheel /Library/LaunchDaemons/openvpn.plist
	
	# Load and execute the LaunchDaemon
	launchctl load /Library/LaunchDaemons/openvpn.plist
	fi
else
	echo `"we did not receive a HTTP 200 ok from the server`" > /Library/Logs/Microsoft/eduVpnDeployment.log
	echo `$response > /Library/Logs/Microsoft/eduVpnDeployment.log
fi" | Out-File -Encoding "UTF8" -FilePath "$PSScriptRoot\macOS_Intune_management_script.sh"

echo "$PSScriptRoot\macOS_management_script.ps1 has been created"
