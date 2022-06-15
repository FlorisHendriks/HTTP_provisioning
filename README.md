# HTTP bulk provisioning
eduVPN is used to provide (large groups of) users a secure way to access the internet and their organisational resources. The goal of eduVPN is to replace typical closed-source VPNs with an open-source audited alternative that works seamlessly with an enterprise identity solution.

Currently, eduVPN authorization works as follows: first, a user installs the eduVPN client on a supported device. When starting the client, the user searches for his or her organisation which opens a web page to the organisation's Identity Provider. The Identity Provider verifies the credentials of the user and notifies the OAuth server whether they are valid or not. The OAuth server then sends back an OAuth token to the user. With that OAuth token, the client application requests an OpenVPN or WireGuard configuration file. When the client receives a configuration file, it authenticates to either the OpenVPN or WireGuard server and establishes the connection (see the Figure below for the protocol overview).

![image](https://user-images.githubusercontent.com/47246332/173606649-0ced87bb-f3a0-46b5-93f4-107ccd404e68.png)

A limitation of this authorization protocol is that the VPN connection can only be established after a user logs in to the device. Many organisations offer managed devices, meaning that they are enrolled into (Azure) Active Directory. Often, organisations only allow clients through either a VPN connection to communicate with their (Azure) Active Directory in order to mitigiate potential security risks. However, this can cause problems. If a new user wants to log in to a managed device, the device needs to be able to communicate with Active Directory to verify those credentials. This is not possible because the VPN is not active yet.

Moreover, this authorization protocol can be seen as an extra threshold for the user to use the VPN. The user needs to start up the client, connect and log in (if the configuration is expired).

# Solution
In this document we are going to solve these drawbacks of the current authorization flow by making eduVPN a system VPN that is always on via provisioning. So instead of making the user interact with a eduVPN client to establish a VPN connection we are going to do that via a script that runs in the background. [Initially we solved this by implementing a technical path using Active Directory Certificate Services (ADCS)](https://github.com/FlorisHendriks98/eduVPN-provisioning). This gets the job done but has two significant limitations. Organisations need to implement ADCS and certificate revocation was a bit inelegant. We want to improve this solution by taking another technical path called HTTP bulk provisioning.

With HTTP bulk provisioning we are going to 

Intune has an API called [Graph API](https://docs.microsoft.com/en-us/graph/use-the-api). With that API we can, for example, retrieve a list of managed devices, delete a device and configure a configuration profile .

[The Graph API has support for subscritions when a resource changes](https://docs.microsoft.com/en-us/graph/api/resources/webhooks?context=graph%2Fapi%2F1.0&view=graph-rest-1.0). In order words, the Graph API is able to send a webhook to a service when data is created, updated or deleted. However, we can't use this service. Microsoft only support these subscriptions for specific sets of data. It supports for example users, to-do tasks and Microsoft Teams messages, it does not support devices or managed devices.

[Intune users have thought of workarounds to mitigate this limitation](https://gregramsey.net/2020/03/18/scenario-perform-automation-based-on-device-enrollment-in-microsoft-intune/). However these workarounds and alternatives require extra microsoft services, which can be quite inconvenient to rely on. More over it adds an extra layer of complexity to the solution as we can see in the Figure below.  

![image](https://user-images.githubusercontent.com/47246332/173828661-137ece9a-0995-4285-81d0-001127dea039.png)
  

High-level concept:

![image](https://user-images.githubusercontent.com/47246332/173604610-466940e6-5fa9-45c7-b9af-ea31bc86da8a.png)

