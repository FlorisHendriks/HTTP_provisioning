#!/bin/sh

#
# Deploy an intermediate webserver and set up automatic VPN revocation
#

if ! [ "root" = "$(id -u -n)" ]; then
    echo "ERROR: ${0} must be run as root!"; exit 1
fi

printf "DNS name of the intermediate Web Server: "; read -r INTERMEDIATE_FQDN

printf "DNS name of eduVPN: "; read -r VPN_FQDN

printf "Directory (tenant) ID: "; read -r TENANT_ID

printf "Application (client) ID: "; read -r APPLICATION_ID

printf "Secret token of the registered application: "; read -r SECRET_TOKEN

printf "Token of the admin api from eduVPN: "; read -r ADMIN_API_TOKEN

WEB_FQDN=$(echo "${WEB_FQDN}" | tr '[:upper:]' '[:lower:]')

###############################################################################
# SOFTWARE
###############################################################################

apt update
apt install -y jq

###############################################################################
# APACHE
###############################################################################

cp ./intermediate.example.conf "/etc/apache2/sites-available/${INTERMEDIATE_FQDN}.conf"

mkdir -p "/usr/share/vpn-provisioning/certs"
cp ./MicrosoftIntuneRootCertificate.cer "/usr/share/vpn-provisioning/certs/MicrosoftIntuneRootCertificate.cer"

mkdir -p "/usr/share/vpn-provisioning/web"
cp ./index.php "/usr/share/vpn-provisioning/web"

# update hostname
sed -i "s/vpn.example/${INTERMEDIATE_FQDN}/" "/etc/apache2/sites-available/${INTERMEDIATE_FQDN}.conf"
sed -i "s/vpn.example/${INTERMEDIATE_FQDN}/" "/usr/share/vpn-provisioning/web/index.php"

# update vpn name
sed -i "s/{vpnDNS}/${VPN_FQDN}/" "/usr/share/vpn-provisioning/web/index.php"

# update tenant id
sed -i "s/{tenantId}/${TENANT_ID}/" "/usr/share/vpn-provisioning/web/index.php"

# update application id
sed -i "s/{applicationId}/${APPLICATION_ID}/" "/usr/share/vpn-provisioning/web/index.php"

# update secret application token
sed -i "s/{secretToken}/${SECRET_TOKEN}/" "/usr/share/vpn-provisioning/web/index.php"

# update admin api token
sed -i "s/{adminApiToken}/${ADMIN_API_TOKEN}/" "/usr/share/vpn-provisioning/web/index.php"

###############################################################################
# CERTBOT
###############################################################################

a2ensite "${INTERMEDIATE_FQDN}"
systemctl restart apache2

certbot certonly -d "${INTERMEDIATE_FQDN}" --webroot --webroot-path /var/www/html

sed -i "s/#SSLEngine/SSLEngine/" "/etc/apache2/sites-available/${INTERMEDIATE_FQDN}.conf"
sed -i "s/#Redirect/Redirect/" "/etc/apache2/sites-available/${INTERMEDIATE_FQDN}.conf"

sed -i "s|#SSLCertificateFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/cert.pem|SSLCertificateFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/cert.pem|" "/etc/apache2/sites-available/${INTERMEDIATE_FQDN}.conf"
sed -i "s|#SSLCertificateKeyFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/privkey.pem|SSLCertificateKeyFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/privkey.pem|" "/etc/apache2/sites-available/${INTERMEDIATE_FQDN}.conf"
sed -i "s|#SSLCertificateChainFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/chain.pem|SSLCertificateChainFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/chain.pem|" "/etc/apache2/sites-available/${INTERMEDIATE_FQDN}.conf"

systemctl restart apache2

###############################################################################
# CRON
###############################################################################

mkdir -p "/usr/libexec/vpn-provisioning"
install -m 700 ./revokeVpnConfigs "/usr/libexec/vpn-provisioning/revokeVpnConfigs"
mkdir -p -m 700 "/var/lib/vpn-provisioning"
touch "/var/lib/vpn-provisioning/localDeviceIds.txt"
chmod 666 "/var/lib/vpn-provisioning/localDeviceIds.txt"

sed -i "s/{applicationId}/${APPLICATION_ID}/" "/usr/libexec/vpn-provisioning/revokeVpnConfigs"
sed -i "s/{secretToken}/${SECRET_TOKEN}/" "/usr/libexec/vpn-provisioning/revokeVpnConfigs"
sed -i "s/{adminApiToken}/${ADMIN_API_TOKEN}/" "/usr/libexec/vpn-provisioning/revokeVpnConfigs"
sed -i "s/vpn.example/${VPN_FQDN}/" "/usr/libexec/vpn-provisioning/revokeVpnConfigs"
sed -i "s/{tenantId}/${TENANT_ID}/" "/usr/libexec/vpn-provisioning/revokeVpnConfigs"

cp ./eduVpnProvisioning /etc/cron.d/eduVpnProvisioning
