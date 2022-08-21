# HTTP bulk provisioning
[eduVPN](https://github.com/eduVPN) is used to provide (large groups of) users a secure way to access the internet and their organisational resources. The goal of eduVPN is to replace typical closed-source VPNs with an open-source audited alternative that works seamlessly with an enterprise identity solution.

Currently, eduVPN authorization works as follows: first, a user installs the eduVPN client on a supported device. When starting the client, the user searches for his or her organisation which opens a web page to the organisation's Identity Provider. The Identity Provider verifies the credentials of the user and notifies the OAuth server whether they are valid or not. The OAuth server then sends back an OAuth token to the user. With that OAuth token, the client application requests an OpenVPN or WireGuard configuration file. When the client receives a configuration file, it authenticates to either the OpenVPN or WireGuard server and establishes the connection (see the Figure below for the protocol overview).

![image](https://user-images.githubusercontent.com/47246332/173606649-0ced87bb-f3a0-46b5-93f4-107ccd404e68.png)

A limitation of this authorization protocol is that the VPN connection can only be established after a user logs in to the device. Many organisations offer managed devices, meaning that they are enrolled into (Azure) Active Directory. Often, organisations only allow clients through either a VPN connection to communicate with their (Azure) Active Directory in order to mitigiate potential security risks. However, this can cause problems. If a new user wants to log in to a managed device, the device needs to be able to communicate with Active Directory to verify those credentials. This is not possible because the VPN is not active yet.

Moreover, this authorization protocol can be seen as an extra threshold for the user to use the VPN. The user needs to start up the client, connect and log in (if the configuration is expired).

# Finding a solution
In this document we are going to solve these drawbacks of the current authorization flow by making eduVPN a system VPN that is always on via provisioning. So instead of making the user interact with a eduVPN client to establish a VPN connection we are going to do that via a script that runs in the background. [Initially we solved this by implementing a technical path using Active Directory Certificate Services (ADCS)](https://github.com/FlorisHendriks98/eduVPN-provisioning). This gets the job done but has two significant limitations. Organisations need to implement ADCS and certificate revocation was a bit inelegant. We want to improve this solution by taking another technical path called HTTP bulk provisioning.

With HTTP bulk provisioning the main idea is that, when a device enrolls to Intune, we notify eduVPN. eduVPN generates a VPN configuration for this device. Finally, we send the VPN configuration to Intune and deploys it to the enrolled device. 

## Basic protocol of our solution
Here we describe how we can use WireGuard and OpenVPN client applications to establish a VPN connection that starts on boot.
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
3. Put a plist file in /Library/LaunchDaemons/ (which can be found in the Github repository)

### OpenVPN for Windows
1. [Download OpenVPN Community edition](https://openvpn.net/community-downloads/). When installing the msi, we need to make sure that we also install the OpenVPN tunnel manager service, this is by default not enabled. 
  When using the installer GUI, click customize.
  
  ![image](https://user-images.githubusercontent.com/47246332/185739715-32c5d992-3a22-4d55-b220-fcab7f29c7ca.png)
  
  Enable the openvpn service feature:
  
  ![image](https://user-images.githubusercontent.com/47246332/185739857-77a1c2e3-475e-48cf-99fd-6c079c7cb637.png)

  When using the command line (as admin), we can execute this command:
  
  msiexec /q /n /I \<path to msi installer\> ADDLOCAL=OpenVPN.Service,OpenVPN,Drivers.TAPWindows6,Drivers
  
2. Get VPN configuration file to the device
3. Put the VPN configuration file in the directiory C:\Program Files\OpenVPN\config-auto (or where you installed OpenVPN)
4. Either reboot the device or restart the OpenVPNService (when OpenVPNService is started, a separate OpenVPN
process will be instantiated for each configuration file that is found in \config-auto directory.)
  
### OpenVPN for macOS
1. Install either the [TunnelBlick app](https://tunnelblick.net/downloads.html) or the OpenVPN Homebrew/Macports package.
2. Get VPN configuration file to the device
3. Put a plist file in /Library/LaunchDaemons/ (which can be found in the Github repository)
4. Run the command: Launchctl load \<name_of_plist_file\>.plist

## Getting the VPN configuration file to the device
Step 2 of the high-level protocol is the most difficult part. We need to get the VPN configuration file to the device.
To communicate with Intune we can use its API called [Graph API](https://docs.microsoft.com/en-us/graph/use-the-api). With that API we can, for example, retrieve a list of managed devices, delete a device and configure a configuration profile.

[The Graph API has support for subscriptions when a resource changes](https://docs.microsoft.com/en-us/graph/api/resources/webhooks?context=graph%2Fapi%2F1.0&view=graph-rest-1.0). In other words, the Graph API is able to send a webhook to a service when data is created, updated or deleted. However, we can't use this service. Microsoft only has support for subscriptions to specific sets of data. It supports for example users, to-do tasks and Microsoft Teams messages, but it does not support managed devices.

[Intune users have thought of workarounds to mitigate this limitation](https://gregramsey.net/2020/03/18/scenario-perform-automation-based-on-device-enrollment-in-microsoft-intune/). However, these workarounds require extra microsoft services, which can be quite inconvenient to set up and rely on. Moreover, it adds an extra layer of complexity to the solution as we can see in the Figure below.

![image](https://user-images.githubusercontent.com/47246332/173830140-9f30333d-bc4f-4913-8ede-7f53482aa925.png)

A viable option that remains is polling to determine if a device has been (un)enrolled. We can set up a Powershell daemon that runs e.g. every 5 minutes to check if devices have been (un)enrolled to Intune. If a new device is enrolled, we send the unique device id to eduVPN. eduVPN responds with a VPN configuration for that device. Next, the powershell daemon constructs a powershell/win32app configuration profile in Intune. Intune will then eventually push the configuration on the enrolled device.

If the powershell daemon detects that a device is unenrolled from Intune, it will ask eduVPN to revoke the VPN configuration for that device.

High-level concept:

![image](https://user-images.githubusercontent.com/47246332/173604610-466940e6-5fa9-45c7-b9af-ea31bc86da8a.png)

Unfortunately, a significant limitation of Intune is that we can not easily deploy a configuration for a specific managed device. [The device needs to be in a group in order to be able to deploy the configuration](https://docs.microsoft.com/en-us/graph/api/intune-shared-devicemanagementscript-assign?view=graph-rest-beta). Since every deployment is unique, every managed device needs to be in an unique group. This results into an overload of groups which makes managebility for IT administrators more difficult.

In order to mitigate this, we deploy only one powershell/batch script that is uniform for every managed device. Every enrolled device receives this script and executes it (you can also use a specific group). Based on the profile, it either receives an openVPN or WireGuard configuration file (it uses the preferred protocol configured in the vpn-user-portal config file of eduVPN). Next the script installs an openVPN or WireGuard tunnel service and establishes the VPN connection.

We decided to drop this idea, it is very risky and unsafe to let the device do the token authenticate api call to the eduVPN server. Intune logs the script including the token which an attacker can then easily retrieve.

---

Next, we researched how Intune authenticates devices. In the [specification of the Mobile Device Enrollment Protocol,](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-mde2/4d7eadd5-3951-4f1c-8159-c39e07cbe692?redirectedfrom=MSDN) we read that "The client certificate
is used by the device client to authenticate itself to the enterprise server for device management and downloading enterprise application". Intune is therefore using mutual TLS to authenticate the devices. 

When a device enrolls into Intune, it gets a certificate with the Intune managed device id as Common Name of the certificate. It also contains the tenant ID (the unique identifier of the organisation within Azure) in the extension list of the certificate (under 1.2.840.113556.5.14). The certificate is signed by the Microsoft Intune Root Certification Authority. For Windows this certificate is either stored in the System user certificate store (the device is enrolled only in Intune) or in the Computer certificate store (if the device is enrolled in both Azure AD and Intune). In macOS the device certificate is always stored in the system keychain. 

So how does Intune verify these certificates exactly? Unfortunately there isn't any proper technical documentation (at the time of writing this paper) on Intune device authentication. However, we can make an educated guess how this works. Whenever the device certificate is sent to Microsoft for authentication, Microsoft will check if the tenant ID exists, if the device belongs to that tenant (using the managed device ID in the CN of the certicate) and if the certificate is signed by the Microsoft CA.

We can reuse this Intune device authentication process to authenticate API calls to the eduVPN server:

for macOS:

![sendApiCall(1)(2)(2)(2) drawio](https://user-images.githubusercontent.com/47246332/183854290-7b48b7f2-739c-405c-810e-114f818aad44.png)

for Windows:

![sendApiCall(1)(2)(2)(2) drawio(1)](https://user-images.githubusercontent.com/47246332/183854237-60f4de43-12a5-4c97-bb3f-d6b5a1767ffd.png)

A limitation of this path is that it supports only OpenVPN. OpenVPN, unlike WireGuard, has the feature to authenticate via certificates. We would like to also support WireGuard as that is a more [efficient protocol](https://dl.acm.org/doi/pdf/10.1145/3374664.3379532).

In order to do this we can set up an intermediate webserver between the managed device and eduVPN. When a device enrolls to Intune it will get the Intune certificate. Next we also deploy via Intune a script that is run on the managed device. The script does an API call to the intermediate webserver authenticated with the certificate. Then the webserver checks if the certificate belongs to the correct tenant, if the device belongs to that tenant (using the managed device id) and if the certificate is signed by the Microsoft CA. When the certificate is validated, it requests a VPN config (either OpenVPN or WireGuard at eduVPN. eduVPN sends back a VPN config to the intermediate server. The intermediate server then forwards the config to the managed device. The managed device installs the config and establishes the VPN connection with eduVPN. A high-level overview:

![sendApiCall(1)(2)(2)(2) drawio(3)](https://user-images.githubusercontent.com/47246332/183869452-e755c057-6002-4cb0-adef-bc97358d11dd.png)

# Revocation
Whenever there is a device compromised we only have to delete the device from Intune. On the Intermediate webserver we will keep track of the managed device ids that we send configs to. We will also set an hourly cronjob that uses the Intune API to retrieve the current list of managed device ids. If the managed device id list we keep locally has an id that the list we receive from Intune does not exist we know that that device has been deleted in Intune. The intermediate webserver is then going to ask eduVPN to revoke that VPN connection for that particular managed device. 

The managed device can't request a new config as well, as the intermediate server checks if the managed device id is in the Intune device list.
