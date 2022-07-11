#!/bin/sh

# Catch errors and log it to /Library/Logs/Microsoft/eduVpnDeployment.log
set -e
trap 'catch $? $LINENO' EXIT
catch() {
	if [ "$1" != "0" ]; then
     		echo "Error $1 occurred on $2" > /Library/Logs/Microsoft/eduVpnDeployment.log 
   	fi
}
# Get the managed device id
id=$(security find-certificate -a | awk -F= '/issu/ && /MICROSOFT INTUNE MDM DEVICE CA/ { getline; print $2 }')

# Retrieve config from eduVPN
response=$(curl -o - -i -s -X POST "https://vpn.strategyit.nl/vpn-user-portal/api/v3/deployIntuneConfig?token=256bit_token_placeholder" -d "profile_id=default&user_id=$id")

http_status=$(echo "$response" | awk 'NR==1 {print $2}')

if [ $http_status == "200" ]; then
	# Install the latest Macports version, which is a package manager for macOS
	
	version=$( curl -fs --url 'https://raw.githubusercontent.com/macports/macports-base/master/config/RELEASE_URL' )
	version=${version##*/v}

    	curl -L -O --url "https://github.com/macports/macports-base/releases/download/v${version}/MacPorts-${version}.tar.gz"

	tar -zxf   MacPorts-${version}.tar.gz 2>/dev/null

	cd MacPorts-${version}
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
	rm  -rf  ./MacPorts-${version}	

	# Install and deploy WireGuard tunnel if we received a wireguard-configuration
	vpnProtocol=$(echo "$response" | awk -F':' '/Content-Type/ {print $2}')
	vpnProtocol="$(echo "$vpnProtocol" | tr -d '[:space:]')"

	if [ "$vpnProtocol" == "application/x-wireguard-profile" ]; then
		echo "wireguard"
		#su floris -c "/Users/floris/Downloads/homebrew/bin/brew install wireguard-tools"
		if [ ! -e /etc/wireguard ]; then
			mkdir -m 600 /etc/wireguard/
		fi
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
		if [ ! -e /etc/openvpn ]; then
			mkdir -m 600 /etc/openvpn/
		fi
		echo "$response" | perl -ne 'print unless 1.../^\s$/' > /etc/openvpn/openvpn.ovpn
		port -N install openvpn3
	
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
			<string>/opt/local/bin/ovpncli</string>
			<string>--config</string>
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
	# launchctl load /Library/LaunchDaemons/openvpn.plist

	fi

else
	echo "we did not receive a HTTP 200 ok from the server" > /Library/Logs/Microsoft/eduVpnDeployment.log
	echo $response > /Library/Logs/Microsoft/eduVpnDeployment.log
fi
