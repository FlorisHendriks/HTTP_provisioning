<?php

declare(strict_types=1);

/*
 * eduVPN - End-user friendly VPN.
 *
 * Copyright: 2014-2022, The Commons Conservancy eduVPN Programme
 * SPDX-License-Identifier: AGPL-3.0+
 */

require_once '/usr/share/php/Vpn/Portal/autoload.php';
$baseDir = '/usr/share/vpn-user-portal';

use Vpn\Portal\Cfg\Config;

$platform = $_GET['platform'];
$profile_id = $_GET['profile_id'];

if (!isset($platform) || !isset($profile_id) || $profile_id == '') {
    $config = Config::fromFile($baseDir.'/config/config.php');
?><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>eduVPN Intune-provisioning Management Script Generator</title>
</head>

<body>
<form method="GET">
	<h1>eduVPN Intune-provisioning Management Script Generator</h1>
	<p>This website generates platform-dependent script for IT admins to deploy using Microsoft Endpoint Manager.</p>
	<p>1. Select eduVPN Profile:<br/>
	<select name="profile_id" size="10">
<?php
    foreach ($config->profileConfigList() as $profileConfig) {
        $id = $profileConfig->profileId();
        echo '<option value="'.htmlspecialchars($id).'"'.($id === $profile_id ? ' selected': '').'>'.htmlspecialchars($profileConfig->displayName()).'</option>';
    }
?>
	</select>
	<p>2. Select script platform:<br/>
	<input type="submit" name="platform" value="windows"> <input type="submit" name="platform" value="macos"></p>
</form>
</body><?php
} else {
        switch ($platform) {
        case 'windows':
            header('Content-Type: text/plain');
            header('Content-Disposition: attachment; filename="Install-VPN-Tunnel.ps1"');
?>try {
    # Get managed device id
    $DeviceID = Get-ItemPropertyValue HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot\EstablishedCorrelations -Name EntDMID
    # Get the certificate from either the system user store or the local machine, depends on how you enroll the device.
    $certStorePath = 'Cert:\CurrentUser\My'
    $MachineCertificate = Get-ChildItem -Path $certStorePath | Where-Object { $_.Subject -like "*$DeviceID*" }
    if ($MachineCertificate -eq $null) {
        $certStorePath = 'Cert:\LocalMachine\My'
        $MachineCertificate = Get-ChildItem -Path $certStorePath | Where-Object { $_.Subject -like "*$DeviceID*" }
    }
    if ($MachineCertificate -eq $null) {
        Throw 'We did not find a certificate, is the device enrolled?'
    }
    # Get VPN config and install the tunnel
    try {
        $Response = Invoke-WebRequest -Method 'Post' -Uri 'https://vpn.example/profile/' -UseBasicParsing -Certificate $MachineCertificate -Body @{profile_id = "<?=$profile_id?>"; user_id = "$DeviceID" }
    }
    catch {
        $respStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($respStream)
        $reader.BaseStream.Position = 0
        $responseBody = $reader.ReadToEnd()
        throw "$($_.Exception) `r`n$responseBody"
    }
    if ($Response.StatusCode -eq 200) {
        # winget requires Visual C++ Redistributables
        $vcRuntime140 = Get-Item -Path "$($env:windir)\System32\vcruntime140.dll" -ErrorAction Ignore
        if ($vcRuntime140 -eq $null) {
            $vcRedistUrl = switch ($env:PROCESSOR_ARCHITECTURE) {
                'AMD64' {'https://aka.ms/vs/17/release/vc_redist.x64.exe'}
                'ARM64' {'https://aka.ms/vs/17/release/vc_redist.arm64.exe'}
                'x86' {'https://aka.ms/vs/17/release/vc_redist.x86.exe'}
                default {throw "Unknown platform: $($env:PROCESSOR_ARCHITECTURE)"}
            }
            $vcRedist = "$($env:TEMP)\vc_redist.exe"
            try {
                Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedist
                & $vcRedist /install /quiet
            }
            finally {
                Remove-Item -Path $vcRedist -ErrorAction Ignore
            }
        }

        # Using winget as system user is quite a hassle (https://github.com/microsoft/winget-cli/issues/548).
        # It can not find the winget path by itself so we need to resolve the path
        # (https://call4cloud.nl/2021/05/cloudy-with-a-chance-of-winget/#part3):
        $ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe"
        if ($ResolveWingetPath) {
            $WingetPath = $ResolveWingetPath[-1].Path
        }
        else {
            Throw "Winget not found"
        }
        cd $WingetPath

        switch ($Response.Headers['Content-Type']) {
            'application/x-wireguard-profile' {
                # Install and deploy WireGuard tunnel
                .\winget.exe install WireGuard.WireGuard --silent --accept-package-agreements --accept-source-agreements
                $service = Get-Service -Name 'WireGuardTunnel$eduVPN' -ErrorAction Ignore
                if ($service -ne $null) {
                    $service | Stop-Service
                }

                # We create a new folder in the WireGuard directory.
                # We can't put it in WireGuard\Data directory as that folder is created only when we start the WireGuard application
                # (https://www.reddit.com/r/WireGuard/comments/x6f1gl/missing_data_directory_when_installing_wireguard/)
                New-Item -Path 'C:\Program Files\WireGuard' -Name 'vpn-provisioning' -ItemType 'directory' -ErrorAction Ignore
                # Limit access to the System user and administrators.
                icacls 'C:\Program Files\WireGuard\vpn-provisioning' /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' /grant:r 'Administrators:(OI)(CI)F'

                $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
                [System.IO.File]::WriteAllLines('C:\Program Files\WireGuard\vpn-provisioning\eduVPN.conf', "$Response", $Utf8NoBomEncoding)

                if ($service -eq $null) {
                    & 'C:\Program Files\WireGuard\wireguard.exe' /installtunnelservice 'C:\Program Files\WireGuard\vpn-provisioning\eduVPN.conf'
                } else {
                    $service | Start-Service
                }
            }
            'application/x-openvpn-profile' {
                # Install and deploy OpenVPN tunnel
                .\winget.exe install OpenVPNTechnologies.OpenVPN --silent --accept-package-agreements --accept-source-agreements --override "ADDLOCAL=OpenVPN.Service,OpenVPN,Drivers.TAPWindows6,Drivers"
                $service = Get-Service -Name 'OpenVPNService'
                $service | Stop-Service

                # Limit access to the System user and administrators.
                icacls "C:\Program Files\OpenVPN\config-auto" /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" /grant:r "Administrators:(OI)(CI)F"

                $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
                [System.IO.File]::WriteAllLines('C:\Program Files\OpenVPN\config-auto\eduVPN.ovpn', "$Response", $Utf8NoBomEncoding)

                $service | Start-Service
            }
            default {
                Throw "Unexpected response: $($Response.Headers['Content-Type'])`r`n$Response"
            }
        }
    }
    else {
        Throw "We received statuscode $Response.StatusCode from the eduVPN server, we expected 200"
    }
}
catch {
    $_ | Out-File -FilePath "$($env:TEMP)\Install-VPN-Tunnel.log"
}
<?php
            break;

        case 'macos':
            header('Content-Type: text/plain');
    header('Content-Disposition: attachment; filename="install_vpn_tunnel.sh"');
    $xml_header = '<'.'?xml version="1.0" encoding="UTF-8"?'.'>';
?>#!/bin/bash

LOGFILE=/Library/Logs/Microsoft/install_vpn_tunnel.log

# We start a subprocess so that we can properly log the output
(
id=$(security find-certificate -a | awk -F= '/issu/ && /MICROSOFT INTUNE MDM AGENT CA/ { getline; print $2 }')
id=$(echo $id | tr -d '"')

id=$(echo $id | cut -d ' ' -f1)

deviceId=$(echo $id | cut -f2- -d "-")

echo "$id" > /Library/Logs/Microsoft/id.log

# Retrieve config from eduVPN
response=$( CURL_SSL_BACKEND=secure-transport curl -s -i --cert "$id" -d "profile_id=<?=$profile_id?>&user_id=$deviceId" "https://vpn.example/profile/")

echo "$response" > /Library/Logs/Microsoft/response.log

http_status=$(echo "$response" | awk 'NR==1 {print $2}' | tr -d '\n')

if [ "$http_status" = "200" ]; then

	#Lets create and traverse to a directory where we are allowed to write as root
	mkdir -m 600 /etc/temp/
	cd /etc/temp

	#Get latest macports version
	version=$( curl -fs --url 'https://raw.githubusercontent.com/macports/macports-base/master/config/RELEASE_URL' )
	version=${version##*/v}

	echo "$version" > /Library/Logs/Microsoft/version.log

	curl -L -O --url "https://github.com/macports/macports-base/releases/download/v${version}/MacPorts-${version}.tar.gz"
	tar -zxf   MacPorts-${version}.tar.gz 2>/dev/null
	cd MacPorts-${version}
	CC=/usr/bin/cc ./configure \
		--prefix=/opt/local \
		--with-install-user=root \
		--with-install-group=wheel \
		--with-directory-mode=0755 \
		--enable-readline \
	&& make SELFUPDATING=1 \
	&& make install SELFUPDATING=1

	# update MacPorts itself
	/opt/local/bin/port -dN selfupdate

	# cleanup
	cd ..
	rm  -rf  ./MacPorts-${version}

	if [[ "$response" == *"Interface"* ]]; then
		if [[ ! -e /etc/wireguard ]]; then
			mkdir -m 600 /etc/wireguard/
		fi
		echo "$response" | perl -ne 'print unless 1.../^\s$/' > /etc/wireguard/wg0.conf
		output=$(/opt/local/bin/port -N install wireguard-tools 2>&1)

		# Create a wireguard daemon
		echo "<?=addslashes($xml_header)?>
		<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
		<plist version=\"1.0\">
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
		</plist>" > /Library/LaunchDaemons/wireguard.plist

		# Change the permissions of the openvpn launch daemon
		chown root:wheel /Library/LaunchDaemons/wireguard.plist
		# Load and execute the LaunchDaemon
		launchctl load /Library/LaunchDaemons/wireguard.plist
	else
		# We received an openVPN config
		if [[ ! -e /etc/openvpn ]]; then
			mkdir -m 600 /etc/openvpn/
		fi
		echo "$response" | perl -ne 'print unless 1.../^\s$/' > /etc/openvpn/openvpn.ovpn
		/opt/local/bin/port -N install openvpn3

		echo "<?=addslashes($xml_header)?>
		<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\" >
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
				<string>/etc/openvpn/openvpn.ovpn</string>
			</array>
			<key>KeepAlive</key><false/>
			<key>RunAtLoad</key><true/>
			<key>TimeOut</key>
			<integer>90</integer>
		</dict>
		</plist>" > /Library/LaunchDaemons/openvpn.plist

		# Change the permissions of the openvpn launch daemon
		chown root:wheel /Library/LaunchDaemons/openvpn.plist

		# Load and execute the LaunchDaemon
		launchctl load /Library/LaunchDaemons/openvpn.plist
	fi
else
	echo "we did not receive a HTTP 200 ok from the server"
fi
) >& $LOGFILE
<?php
        break;

    default:
        echo 'unknown platform';
        exit(1);
    }
}
?>