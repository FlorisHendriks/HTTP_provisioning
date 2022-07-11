#!/bin/sh

# Get the managed device id
id=$(security find-certificate -a | awk -F= '/issu/ && /MICROSOFT INTUNE MDM DEVICE CA/ { getline; print $2 }')

# Retrieve config from eduVPN
response=$(curl -o - -i -s -X POST "https://vpn.strategyit.nl/vpn-user-portal/api/v3/deployIntuneConfig?token=256bit_token_placeholder" -d "profile_id=default&user_id=$id")

http_status=$(echo "$response" | awk 'NR==1 {print $2}')

if [ $http_status == "200" ]; then
	# Install Macports, a package manager for macOS
	curl -L https://github.com/macports/macports-base/releases/download/v2.7.2/MacPorts-2.7.2-12-Monterey.pkg > /tmp/macports.pkg
	installer -pkg /tmp/macports.pkg -target /
	
	# Determine which protocol we are going to use
	vpnProtocol=$(echo "$response" | awk -F':' '/Content-Type/ {print $2}')
	vpnProtocol="$(echo "$vpnProtocol" | tr -d '[:space:]')"
	
	# Install and deploy WireGuard tunnel if we received a wireguard-configuration
	if [ "$vpnProtocol" == "application/x-wireguard-profile" ]; then
		echo "wireguard"
		#su floris -c "/Users/floris/Downloads/homebrew/bin/brew install wireguard-tools"
		mkdir -m 600 /etc/wireguard/
		echo "$response" | perl -ne 'print unless 1.../^\s$/' > /etc/wireguard/wg0.conf
		port -N install wireguard-tools

		# Create a wireguard daemon
		echo "<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
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
		mkdir -m 600 /etc/openvpn/
		echo "$response" | perl -ne 'print unless 1.../^\s$/' > /etc/openvpn/openvpn.conf
		port -N install openvpn2
	
		echo "<?xml version='1.0' encoding='UTF-8'?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
		"http://www.apple.com/DTDs/PropertyList-1.0.dtd" >
		<plist version='1.0'>
		<dict>
		<key>StandardOutPath</key>
		<string>/var/logs/startVPNoutput.log</string>
		<key>StandardErrorPath</key>
		<string>/var/logs/startVPNerror.log</string>
		<key>Label</key><string>eduvpn.openvpn</string>
		<key>ProgramArguments</key>
		<array>
			<string>/opt/local/sbin/openvpn2</string>
			<string>--config</string>
			<string>/etc/openvpn/openvpn.conf</string>
		</array>
		<key>KeepAlive</key><false/>
		<key>RunAtLoad</key><true/>
		</dict>
		</plist>" > /Library/LaunchDaemons/openvpn.plist

	# Change the permissions of the openvpn launch daemon
	chown root:wheel /Library/LaunchDaemons/openvpn.plist
	
	# Load and execute the LaunchDaemon
	launchctl load /Library/LaunchDaemons/openvpn.plist

	fi

else
	echo "we did not receive a HTTP 200 ok from the server"
	echo $response
fi 
