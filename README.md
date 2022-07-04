# HTTP bulk provisioning
[eduVPN](https://github.com/eduVPN) is used to provide (large groups of) users a secure way to access the internet and their organisational resources. The goal of eduVPN is to replace typical closed-source VPNs with an open-source audited alternative that works seamlessly with an enterprise identity solution.

Currently, eduVPN authorization works as follows: first, a user installs the eduVPN client on a supported device. When starting the client, the user searches for his or her organisation which opens a web page to the organisation's Identity Provider. The Identity Provider verifies the credentials of the user and notifies the OAuth server whether they are valid or not. The OAuth server then sends back an OAuth token to the user. With that OAuth token, the client application requests an OpenVPN or WireGuard configuration file. When the client receives a configuration file, it authenticates to either the OpenVPN or WireGuard server and establishes the connection (see the Figure below for the protocol overview).

![image](https://user-images.githubusercontent.com/47246332/173606649-0ced87bb-f3a0-46b5-93f4-107ccd404e68.png)

A limitation of this authorization protocol is that the VPN connection can only be established after a user logs in to the device. Many organisations offer managed devices, meaning that they are enrolled into (Azure) Active Directory. Often, organisations only allow clients through either a VPN connection to communicate with their (Azure) Active Directory in order to mitigiate potential security risks. However, this can cause problems. If a new user wants to log in to a managed device, the device needs to be able to communicate with Active Directory to verify those credentials. This is not possible because the VPN is not active yet.

Moreover, this authorization protocol can be seen as an extra threshold for the user to use the VPN. The user needs to start up the client, connect and log in (if the configuration is expired).

# Finding a solution
In this document we are going to solve these drawbacks of the current authorization flow by making eduVPN a system VPN that is always on via provisioning. So instead of making the user interact with a eduVPN client to establish a VPN connection we are going to do that via a script that runs in the background. [Initially we solved this by implementing a technical path using Active Directory Certificate Services (ADCS)](https://github.com/FlorisHendriks98/eduVPN-provisioning). This gets the job done but has two significant limitations. Organisations need to implement ADCS and certificate revocation was a bit inelegant. We want to improve this solution by taking another technical path called HTTP bulk provisioning.

With HTTP bulk provisioning the main idea is that, when a device enrolls to Intune, we notify eduVPN. eduVPN generates a VPN configuration for this device. Finally, we send the VPN configuration to Intune and deploys it to the enrolled device. 

To communicate with Intune we can use its API called [Graph API](https://docs.microsoft.com/en-us/graph/use-the-api). With that API we can, for example, retrieve a list of managed devices, delete a device and configure a configuration profile.

[The Graph API has support for subscriptions when a resource changes](https://docs.microsoft.com/en-us/graph/api/resources/webhooks?context=graph%2Fapi%2F1.0&view=graph-rest-1.0). In other words, the Graph API is able to send a webhook to a service when data is created, updated or deleted. However, we can't use this service. Microsoft only has support for subscriptions to specific sets of data. It supports for example users, to-do tasks and Microsoft Teams messages, but it does not support managed devices.

[Intune users have thought of workarounds to mitigate this limitation](https://gregramsey.net/2020/03/18/scenario-perform-automation-based-on-device-enrollment-in-microsoft-intune/). However, these workarounds require extra microsoft services, which can be quite inconvenient to set up and rely on. Moreover, it adds an extra layer of complexity to the solution as we can see in the Figure below.

![image](https://user-images.githubusercontent.com/47246332/173830140-9f30333d-bc4f-4913-8ede-7f53482aa925.png)

A viable option that remains is polling to determine if a device has been (un)enrolled. We can set up a Powershell daemon that runs e.g. every 5 minutes to check if devices have been (un)enrolled to Intune. If a new device is enrolled, we send the unique device id to eduVPN. eduVPN responds with a VPN configuration for that device. Next, the powershell daemon constructs a powershell/win32app configuration profile in Intune. Intune will then eventually push the configuration on the enrolled device.

If the powershell daemon detects that a device is unenrolled from Intune, it will ask eduVPN to revoke the VPN configuration for that device.

High-level concept:

![image](https://user-images.githubusercontent.com/47246332/173604610-466940e6-5fa9-45c7-b9af-ea31bc86da8a.png)

Unfortunately, a significant limitation of Intune is that we can not easily deploy a configuration for a specific managed device. [The device needs to be in a group in order to be able to deploy the configuration](https://docs.microsoft.com/en-us/graph/api/intune-shared-devicemanagementscript-assign?view=graph-rest-beta). Since every deployment is unique, every managed device needs to be in an unique group. This results into an overload of groups which makes managebility for IT administrators more difficult.

In order to mitigate this, we deploy only one powershell/batch script that is uniform for every managed device. This contains an admin token that requests a VPN configuration for that device:

![eduVPN provisioning(1) drawio](https://user-images.githubusercontent.com/47246332/175930131-8fdd0b31-9521-474f-a357-433337fcecf5.png)

We also need to be able to revoke the VPN configuration files automatically, so we run a powershell daemon that revokes them whenever an Intune device is deleted:

![eduVPN provisioning(1) drawio(1)](https://user-images.githubusercontent.com/47246332/175930657-1c1e9cff-9344-4feb-9e9f-9fe896813e20.png)

This is the path we are going to implement to make eduVPN a system VPN.

# Implementation

## Windows
**NOTE**: We also have an instruction video on how to deploy eduVPN as a system VPN [here]() 

### Prerequisites
* A Windows device with Windows 10 or later
* Access to an Intune tenant.
* Git installed.
* A deployed eduVPN server with support for provisioning
* [A registered app in Azure](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)
* [Create a client secret for the app](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#option-2-create-a-new-application-secret)
* [Find the token endpoint for the app](https://user-images.githubusercontent.com/47246332/177116133-9e070012-bb2a-4134-8263-e1c1a71add8b.png)

Here we create a powershell Intune deployment script adapted to your organisation and deploy a powershell daemon. 

### Step 1
Open powershell as administrator and clone the repository:
```powershell
git clone https://github.com/FlorisHendriks98/HTTP_bulk_provisioning.git
```
Traverse to the repository:
```powershell
cd HTTP_bulk_provisioning
```
### Step 2
Run Create_Intune_Management_Script.ps1, specify the following parameters:

* -p you **must** specify the VPN profile
* -s you **must** specify the hostname of the VPN server
* -t you **must** specify the token which you can receive from the eduVPN vpn-user-portal or api.

Example:
```powershell
./Create_Intune_Management_Script.ps1 -p "default" -s "vpn.example.com" -t "256bit_token_placeholder"
```
In the same directory the file Intune_Management_Script.ps1 is created.

Next, run Create_Powershell_Daemon.ps1 which is located in the same directory. Specify the following parameters: 

* -s you **must** specify the hostname of the VPN server
* -t you **must** specify the token which you can receive from the eduVPN vpn-user-portal or api
* -id you **must** specify the identifier of the app you registered (see prerequisites)
* -cs you **must** specify the client secret you created for the app (see prerequisites)
* -e you **must** specify the token endpoint (see prerequisites)

```powershell
./Create_Powershell_Daemon.ps1 -s "vpn.example.com" -t "256bit_token_placeholder" -id "Application_ID" -cs "client_secret" -e "https://login.microsoftonline.com/hexadecimals_placeholder/oauth2/v2.0/token"
```

### Step 4
Add the Intune_management_script.ps1 to the Intune portal.

https://user-images.githubusercontent.com/47246332/176458532-2f1dd9b2-50a9-4e9d-9c0f-9c65da325ccd.mp4

### Step 5
Now we deploy a powershell daemon that revokes an eduVPN config whenever a managed device gets removed from Intune.


## 


