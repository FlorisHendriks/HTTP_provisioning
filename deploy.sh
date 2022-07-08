#!/bin/sh

# This line retrieves the managed device id from the macOS device. I realize that this is very prone to errors but during 
# my research I did not find any better way to retrieve this id
id=$(security find-certificate -a | awk -F= '/issu/ && /MICROSOFT INTUNE MDM DEVICE CA/ { getline; print $2 }')

echo $id
response=$(curl -o - -i -s -X POST "https://vpn.strategyit.nl/vpn-user-portal/api/v3/deployIntuneConfig?token=256bit_token_placeholder" -d 'profile_id=default&user_id="foobar"')
echo "$response" > test.txt

http_status=$(echo "$response" | awk 'NR==1 {print $2}')
echo "$response"
curl -i -s -X POST "https://vpn.strategyit.nl/vpn-user-portal/api/v3/deployIntuneConfig?token=256bit_token_placeholder" -d 'profile_id=default&user_id=foobar'
if [ $http_status == "200" ]; then
	# Install and deploy WireGuard tunnel if we received a wireguard-configuration
	echo '\n'
	test=$(echo "$response" | awk -F':' '/Content-Type/ {print $2}')
	test2="$(echo "${test}" | tr -d '[:space:]')"
	echo "$test2"
	echo "${#test2}"
	
	if [ "$test2" == "application/x-wireguard-profile" ]; then

		# We need to run homebrew as local user, otherwise homebrew gets to many permissions
		#user=$(users | awk '{print $1}')
		#mkdir homebrew && curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C homebrew
		#su floris -c "/Users/floris/Downloads/homebrew/bin/brew install wireguard-tools"
		mkdir -m 600 /etc/wireguard/
		echo "$response" | perl -ne 'print unless 1.../^\s$/' > /etc/wireguard/wg0.conf
		/Users/floris/Downloads/homebrew/bin/wg-quick up /etc/wireguard/wg0.conf
	else
	echo "testttt"

	fi

else
	echo "we did not receive a HTTP 200 ok from the server"
	echo $response
fi 

echo "test"
