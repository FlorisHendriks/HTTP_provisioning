# HTTP bulk provisioning
eduVPN is used to provide (large groups of) users a secure way to access the internet and their organisational resources. The goal of eduVPN is to replace typical closed-source VPNs with an open-source audited alternative that works seamlessly with an enterprise identity solution.

Currently, eduVPN authorization works as follows: first, a user installs the eduVPN client on a supported device. When starting the client, the user searches for his or her organisation which opens a web page to the organisation's Identity Provider. The Identity Provider verifies the credentials of the user and notifies the OAuth server whether they are valid or not. The OAuth server then sends back an OAuth token to the user. With that OAuth token, the client application requests an OpenVPN or WireGuard configuration file. When the client receives a configuration file, it authenticates to either the OpenVPN or WireGuard server and establishes the connection (see the Figure below for the protocol overview).

![image](https://user-images.githubusercontent.com/47246332/173606649-0ced87bb-f3a0-46b5-93f4-107ccd404e68.png)



#Solution 
Intune has an API called [Graph API](https://docs.microsoft.com/en-us/graph/use-the-api). With that API we can, for example, retrieve a list of managed devices, delete a device and configure a configuration profile .   

High-level concept:

![image](https://user-images.githubusercontent.com/47246332/173604610-466940e6-5fa9-45c7-b9af-ea31bc86da8a.png)

