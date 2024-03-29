# HTTP provisioning
[eduVPN](https://github.com/eduVPN) is used to provide (large groups of) users a secure way to access the internet and their organisational resources. The goal of eduVPN is to replace typical closed-source VPNs with an open-source audited alternative that works seamlessly with an enterprise identity solution.

Currently, eduVPN authorization works as follows: first, a user installs the eduVPN client on a supported device. When starting the client, the user searches for his or her organisation which opens a web page to the organisation's Identity Provider. The Identity Provider verifies the credentials of the user and notifies the OAuth server whether they are valid or not. The OAuth server then sends back an OAuth token to the user. With that OAuth token, the client application requests a WireGuard configuration file. When the client receives a configuration file, it authenticates to the WireGuard server and establishes the connection (see the Figure below for the protocol overview).

![image](https://user-images.githubusercontent.com/47246332/173606649-0ced87bb-f3a0-46b5-93f4-107ccd404e68.png)

A limitation of this authorization protocol is that the VPN connection can only be established after a user logs in to the device. Many organisations offer managed devices, meaning that they are enrolled into (Azure) Active Directory. Often, organisations only allow clients through either a VPN connection to communicate with their (Azure) Active Directory in order to mitigiate potential security risks. However, this can cause problems. If a new user wants to log in to a managed device, the device needs to be able to communicate with Active Directory to verify those credentials. This is not possible because the VPN is not active yet.

Moreover, this authorization protocol can be seen as an extra threshold for the user to use the VPN. The user needs to start up the client, connect and log in (if the configuration is expired).

# Finding a solution
In this document we are going to solve these drawbacks of the current authorization flow by making eduVPN a system VPN that is always on via provisioning. So instead of making the user interact with a eduVPN client to establish a VPN connection we are going to realize that via a daemon. [Initially we solved this by implementing a technical path using Active Directory Certificate Services (ADCS)](https://github.com/FlorisHendriks/eduVPN-provisioning). This gets the job done but has two significant limitations. Organisations need to implement ADCS and certificate revocation was a bit inelegant. We want to improve this solution by taking another technical path called HTTP provisioning. 

## High-level protocol of our solution
Here we describe how we can use WireGuard client application to establish a VPN connection that starts on boot.
### Wireguard for Windows
1. [Download](https://www.wireguard.com/install/) and install WireGuard on the device
2. Get VPN configuration file to the device
3. Run the following command as admin (or system user):

\<path to WireGuard.exe\> /installtunnelservice \<path to WireGuard config file\>

e.g.

"C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice C:\wg0.conf
### Wireguard for macOS
It isn't possible to start a WireGuard tunnel on boot with the WireGuard macOS app. It is however possible to do this with wg-quick which can be installed along with the wireguard-tools package. 
1. Install wireguard-tools which can be installed using either [Homebrew](https://brew.sh/) or [Macports](https://www.macports.org/install.php).
2. Get VPN configuration file to the device
3. Put a plist file in /Library/LaunchDaemons/ (examples can be found in the Github repository)
4. Run the command: sudo launchctl load \<name_of_plist_file\>.plist

## Getting the VPN configuration file to the device
Step 2 of the high-level protocol is the most difficult part. We need to get the VPN configuration file to the device.

[When it comes down to distributing files to managed devices we mainly have two options](https://www.reddit.com/r/WireGuard/comments/p9deno/wireguard_windows_gpo_deployment_possible/):
1. Distribute the config files via GPO
2. Use a file copy command (e.g. Robocopy) to the managed devices via SMB.

The first option is not [supported by macOS](https://stackoverflow.com/questions/44568362/i-am-looking-for-a-way-to-push-mac-software-from-ad-server-to-connected-mac-clie) without a third party tool.

The second option is supported by macOS but you have to enable SMB manually which can be time consuming. Moreover, SMB has historically shown that it is [not safe to use](https://cve.mitre.org/cgi-bin/cvekey.cgi?keyword=smb), so we would like to refrain from that protocol.

In order to properly be able to manage macOS as well, organisations often choose to use the mobile device management service Microsoft Intune. We therefore explored Intune to see if it can help us delegate these VPN configuration files.

---

To communicate with Intune we can use its API called [Graph API](https://docs.microsoft.com/en-us/graph/use-the-api). With that API we can, for example, retrieve a list of managed devices, delete a device and configure a configuration profile.

[The Graph API has support for subscriptions when a resource changes](https://docs.microsoft.com/en-us/graph/api/resources/webhooks?context=graph%2Fapi%2F1.0&view=graph-rest-1.0). In other words, the Graph API is able to send a webhook to a service when data is created, updated or deleted. However, we can't use this service. Microsoft only has support for subscriptions to specific sets of data. It supports for example users, to-do tasks and Microsoft Teams messages, but it does not support managed devices.

[Intune users have thought of workarounds to mitigate this limitation](https://gregramsey.net/2020/03/18/scenario-perform-automation-based-on-device-enrollment-in-microsoft-intune/). However, these workarounds require extra microsoft services, which can be quite inconvenient (and costly) to set up and rely on. Moreover, it adds an extra layer of complexity to the solution as we can see in the Figure below.

![image](https://user-images.githubusercontent.com/47246332/173830140-9f30333d-bc4f-4913-8ede-7f53482aa925.png)

A viable option that remains is polling to determine if a device has been (un)enrolled. We can set up a Powershell daemon that runs e.g. every 5 minutes to check if devices have been (un)enrolled to Intune. If a new device is enrolled, we send the unique device id to eduVPN. eduVPN responds with a VPN configuration for that device. Next, the powershell daemon constructs a powershell/win32app configuration profile in Intune. Intune will then eventually push the configuration on the enrolled device.

If the powershell daemon detects that a device is unenrolled from Intune, it will ask eduVPN to revoke the VPN configuration for that device.

High-level concept:

![image](https://user-images.githubusercontent.com/47246332/173604610-466940e6-5fa9-45c7-b9af-ea31bc86da8a.png)

Unfortunately, a significant limitation of Intune is that we can not easily deploy a configuration for a specific managed device. [The device needs to be in a group in order to be able to deploy the configuration](https://docs.microsoft.com/en-us/graph/api/intune-shared-devicemanagementscript-assign?view=graph-rest-beta). Since every deployment is unique, every managed device needs to be in an unique group. This results into an overload of groups which makes managebility for IT administrators more difficult.

In order to mitigate this, we deploy only one powershell/batch script that is uniform for every managed device. Every enrolled device receives this script and executes it (you can also use a specific group). It receives WireGuard configuration file using an API call (it uses the preferred protocol configured in the vpn-user-portal config file of eduVPN). Next the script installs a WireGuard tunnel service and establishes the VPN connection.

Initially we authenticated the API call to retceive a configuration file with a static 256 bit token. However, we decided to drop this idea, it is very risky and unsafe to let the device do the token authenticate api call to the eduVPN server. Intune logs the script including the token which an attacker can then easily retrieve. We were therefore trying to find a safer authentication approach.

---

Next, we researched how Intune authenticates devices. In the [specification of the Mobile Device Enrollment Protocol,](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-mde2/4d7eadd5-3951-4f1c-8159-c39e07cbe692?redirectedfrom=MSDN) we read that "The client certificate
is used by the device client to authenticate itself to the enterprise server for device management and downloading enterprise application". Intune is therefore using mutual TLS to authenticate the devices. 

When a device enrolls into Intune, it gets a certificate with the Intune managed device id as Common Name of the certificate. It also contains the tenant ID (the unique identifier of the organisation within Azure) in the extension list of the certificate [(under 1.2.840.113556.5.14)](https://www.reddit.com/r/Intune/comments/w3jroh/comment/igytm5o/?utm_source=share&utm_medium=web2x&context=3). The certificate is signed by the Microsoft Intune Root Certification Authority. For Windows this certificate is either stored in the System user certificate store (the device is enrolled only in Intune) or in the Computer certificate store (if the device is enrolled in both Azure AD and Intune). In macOS the device certificate is always stored in the system keychain. 

So how does Intune verify these certificates exactly? Unfortunately there isn't any proper technical documentation (at the time of writing this paper) on Intune device authentication. However, we can make an educated guess how this works. Whenever the device certificate is sent to Microsoft for authentication, Microsoft will check if the tenant ID exists, if the device belongs to that tenant (using the managed device ID in the CN of the certicate) and if the certificate is signed by the Microsoft CA.

We can reuse this Intune device authentication process to authenticate API calls to the eduVPN server:

for macOS:

![sendApiCall(1)(2)(2)(2) drawio](https://user-images.githubusercontent.com/47246332/183854290-7b48b7f2-739c-405c-810e-114f818aad44.png)

for Windows:

![sendApiCall(1)(2)(2)(2) drawio(1)](https://user-images.githubusercontent.com/47246332/183854237-60f4de43-12a5-4c97-bb3f-d6b5a1767ffd.png)

A limitation of this path is that it supports only OpenVPN. OpenVPN, unlike WireGuard, has the feature to authenticate via certificates. We would like to support WireGuard as that is a more [efficient protocol](https://dl.acm.org/doi/pdf/10.1145/3374664.3379532).

In order to do this we can set up an intermediate webserver between the managed device and eduVPN. When a device enrolls to Intune it will get the Intune certificate. Next we also deploy via Intune a script that is run on the managed device. The script does an API call to the intermediate webserver authenticated with the certificate. Then the webserver checks if the certificate belongs to the correct tenant, if the device belongs to that tenant (using the managed device id) and if the certificate is signed by the Microsoft CA. When the certificate is validated, it requests a VPN config at eduVPN. eduVPN sends back a VPN config to the intermediate server. The intermediate server then forwards the config to the managed device. The managed device installs the config and establishes the VPN connection with eduVPN. A high-level overview:

![sendApiCall(1)(2)(2)(2) drawio(3)](https://user-images.githubusercontent.com/47246332/183869452-e755c057-6002-4cb0-adef-bc97358d11dd.png)

# Revocation
Whenever there is a device compromised we only have to delete the device from Intune. On the Intermediate webserver we will keep track of the managed device ids that we send configs to. We will also set a cronjob that runs every 5 mintues. The script uses the Intune API to retrieve the current list of managed device ids. If the managed device id list we keep locally has an id that the list we receive from Intune does not exist we know that that device has been deleted in Intune. The intermediate webserver is then going to ask eduVPN to revoke that VPN connection for that particular managed device. 

The managed device can't request a new config as well, as the intermediate server checks if the managed device id is in the Intune device list.

# Security considerations
If an adversary can hijack a managed device then he or she can use the tunnel service to communicate with devices that are behind the system VPN. Furthermore, there is also a possibility that an adversary can retrieve a managed device certificate so that he or she can retrieve new VPN configuration files. In order to retrieve or use a certificate the adversary needs to hijack one of the managed devices and then has to escalate privileges to the administrator role.

# Technical limitations
This path was easy to implement on Windows. macOS, on the other hand, had two main technical difficulties we had to overcome. 

The first one is the usage of [curl](https://curl.se/docs/manpage.html). Curl on macos has support (if you built it against [Secure Transport](https://curl.se/docs/manpage.html#-E)) to use certificates from the keychain where the Intune device certificates are stored. Unfortunately, if you specify the Intune device certificate it does not send the intermediate certificate along with the request. In order to mitigate this we need to define the intermediate certificate in Apache in order to be able to verify Intune device certificates.

The other one is that macOS has implemented access control on the private key of certificates (see the Figure below). This means that only these specified applications are allowed to use the Intune managed device certificate for mutual TLS. Unfortunately, curl is a bash command which is not allowed to access this private key by default.

![image](https://user-images.githubusercontent.com/47246332/188156739-d6a65c5c-e24a-4f83-b14c-5a368aa554fb.png)

In order to mitigate this we are going to use a different certificate that Intune puts on the macOS device. This certificate has a private key that every application can use (you still need administrator privileges to access the certificate). The certificate is called IntuneMDMAgent-{managedDeviceId} and is signed by the intermediate certificate Microsoft Intune MDM Agent CA.

This limitation is currently under ![discussion](https://github.com/curl/curl/discussions/12987)

# Implementation
## Prerequisites
* An Intune enrolled Windows 10/11 device or MacOS Monterey device
* A deployed eduVPN server with:
  - ![admin API enabled](https://docs.eduvpn.org/server/v3/admin-api.html#admin-api)
  - ![SSL enabled](https://docs.eduvpn.org/server/v3/deploy-debian.html#lets-encrypt)
  - ![A profile configured for ``System VPN'' with preferred protocol set to ```Wireguard```](https://docs.eduvpn.org/server/v3/deploy-debian.html#lets-encrypt)
* Access to a Microsoft Endpoint Manager (Intune) tenant.
* Working DNS entry for your intermediate webserver, e.g. intermediate.example.org.

## Step 1
We first need to register an application in Azure. This will allow us to do API calls to Intune. Please refer to the tutorial below for additional guidance on how to register the application.

* [Register an app in Azure](https://docs.microsoft.com/en-us/power-apps/developer/data-platform/walkthrough-register-app-azure-active-directory)
* Go to API permissions and add the _Application permissions_ "DeviceManagementManagedDevices.Read.All" and "DeviceManagementManagedDevices.ReadWrite.All" to the "Microsoft Graph" API.
* Grant admin consent for the above privileges.
* Go to Certificates & secrets and create a new client secret. Be sure to temporarily save the ```value``` of the secret.
* Retrieve the Azure Tenant ID, and Application client ID in Azure.
* ![Retrieve the admin API token of the system vpn eduvpn server](https://docs.eduvpn.org/server/v3/admin-api.html#configuration).
## Step 2
Perform these steps on the eduVPN server:

    $ git clone https://github.com/FlorisHendriks/HTTP_provisioning.git
    $ cd HTTP_provisioning/resources/
    $ sudo ./deploy_intermediate_<debian/fedora>.sh

The script will ask to enter the values of step 1 in order to set everything up properly.

## Step 3
Open up a browser and visit https://intermediate.example.org/management_script/ (replace hostname with your intermediate server FQDN) to generate Install-VPN-Tunnel.ps1 and install_vpn_tunnel.sh management scripts.

## Step 4
Place and configure the Install-VPN-Tunnel.ps1 and install_vpn_tunnel.sh in Intune. Make sure that you configure the Windows PowerShell script to run in a 64 bit PowerShell host (see Figure below).

![image](https://user-images.githubusercontent.com/47246332/188602159-d199b46b-71ac-4fb4-943f-cfac12ed29b9.png)

The scripts are pushed to the devices and will deploy the system VPN.

# Tutorial

https://user-images.githubusercontent.com/47246332/189675495-105cdfa0-3b7a-4c7a-bf53-f768b670d011.mp4

## Troubleshooting
If some things do not go as planned you can check the log files.
* On the Windows client it is stored at "C:\Windows\Temp\Install-VPN-Tunnel.log"
* On the macOS client it is stored at "/Library/Logs/Microsoft/install_vpn_tunnel.log"
* Revocation logs can be found at "/var/lib/vpn-provisioning/revocation.log"

# Future Work
* Lots and lots of testing, finding edge cases and debug potential issues.
* Improve the code and let it run more efficiently
