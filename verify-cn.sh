#!/bin/sh

depth = "$0"
certificate = "$1"

if [ "$depth" -eq 0 ]; then
        # Parse out the common name substring in the X509 subject string.
        clientCN="$(openssl x509 -noout -subject -in "$1" -nameopt multiline | sed -n 's/ *commonName *= //p')"

        # Get the Intune token so that we are allowed to do api calls
        postParams='client_id=client_id&scope=https://graph.microsoft.com/.default&client_secret=client_secret_placeholder&grant_type=client_credentials'
        tokenResponse="$(curl -X POST 'https://login.microsoftonline.com/a9d8059a-38d4-4690-bdd4-9f7d0662d8d0/oauth2/v2.0/token' -X POST -d "$postParams")"
        token="$(echo "$tokenResponse" | grep -o '"access_token":"[^"]*' | grep -o '[^"]*$')"

        # Receive the managed device ids of the Intune tenant
        url='https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$select=id'
        response="$(curl -X GET "$url" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -H 'ConsistencyLevel: eventual')"
        managedIds="$(echo "$response" | grep -o '"access_token":"[^"]*' | grep -o '[^"]*$')"


        # Accept the connection if the X509 common name
        # string matches the managed device Id of Intune.
        for id in $managedIds
        do
                if [ "$id" = "$clientCN" ]; then
                        exit 0
                fi
        done

        # Authentication failed -- Either we could not parse
        # the X509 subject string, or the common name in the
        # subject string didn't match the passed cn argument.
        exit 1
else
        # Depth is nonzero, tell OpenVPN to continue process the certificate chain.
        exit 0
fi