#!/bin/sh

#
# Deploy an intermediate webserver and set up automatic VPN revocation
#

if ! [ "root" = "$(id -u -n)" ]; then
    echo "ERROR: ${0} must be run as root!"; exit 1
fi

VPN_URL=http://localhost

[ -f /etc/vpn-provisioning ] && . /etc/vpn-provisioning

printf "DNS name of the intermediate Web Server [%s]: " "${INTERMEDIATE_FQDN}"; read -r USER_INPUT
INTERMEDIATE_FQDN=$(echo "${USER_INPUT:-${INTERMEDIATE_FQDN}}" | tr '[:upper:]' '[:lower:]')

printf "URL of eduVPN server [%s]: " "${VPN_URL}"; read -r USER_INPUT
VPN_URL=${USER_INPUT:-${VPN_URL}}

printf "Token of the admin API from eduVPN [%s]: " "${ADMIN_API_TOKEN:0:3}****"; read -r USER_INPUT
ADMIN_API_TOKEN=${USER_INPUT:-${ADMIN_API_TOKEN}}

printf "Azure Tenant ID [%s]: " "${TENANT_ID}"; read -r USER_INPUT
TENANT_ID=${USER_INPUT:-${TENANT_ID}}

printf "Application (client) ID [%s]: " "${APPLICATION_ID}"; read -r USER_INPUT
APPLICATION_ID=${USER_INPUT:-${APPLICATION_ID}}

printf "Secret token of the registered application [%s]: " "${SECRET_TOKEN:0:3}****"; read -r USER_INPUT
SECRET_TOKEN=${USER_INPUT:-${SECRET_TOKEN}}

###############################################################################
# SOFTWARE
###############################################################################

# install software (dependencies)
/usr/bin/dnf -y install jq

###############################################################################
# APACHE
###############################################################################

cp ./intermediate.example.conf "/etc/httpd/conf.d/${INTERMEDIATE_FQDN}.conf"

mkdir -p "/usr/share/vpn-provisioning/certs"
cp ./MicrosoftIntuneRootCertificate.cer "/usr/share/vpn-provisioning/certs/MicrosoftIntuneRootCertificate.cer"

[ -f "/usr/share/vpn-provisioning/web/index.php" ] && rm "/usr/share/vpn-provisioning/web/index.php"
mkdir -p "/usr/share/vpn-provisioning/web/profile"
cp web/profile/index.php "/usr/share/vpn-provisioning/web/profile"
mkdir -p "/usr/share/vpn-provisioning/web/management_script"
cp web/management_script/index.php "/usr/share/vpn-provisioning/web/management_script"

# update hostname
sed -i "s/vpn.example/${INTERMEDIATE_FQDN}/" "/etc/httpd/conf.d/${INTERMEDIATE_FQDN}.conf"
sed -i "s/vpn.example/${INTERMEDIATE_FQDN}/" "/usr/share/vpn-provisioning/web/profile/index.php"
sed -i "s/vpn.example/${INTERMEDIATE_FQDN}/" "/usr/share/vpn-provisioning/web/management_script/index.php"

# update vpn name
VPN_URL_SED=${VPN_URL//\//\\/}
sed -i "s/{vpnUrl}/${VPN_URL_SED}/" "/usr/share/vpn-provisioning/web/profile/index.php"

# update tenant id
sed -i "s/{tenantId}/${TENANT_ID}/" "/usr/share/vpn-provisioning/web/profile/index.php"

# update application id
sed -i "s/{applicationId}/${APPLICATION_ID}/" "/usr/share/vpn-provisioning/web/profile/index.php"

# update secret application token
sed -i "s/{secretToken}/${SECRET_TOKEN}/" "/usr/share/vpn-provisioning/web/profile/index.php"

# update admin api token
sed -i "s/{adminApiToken}/${ADMIN_API_TOKEN}/" "/usr/share/vpn-provisioning/web/profile/index.php"

###############################################################################
# CERTBOT
###############################################################################

systemctl stop httpd

certbot certonly --standalone -d "${INTERMEDIATE_FQDN}"

cat << EOF > /etc/sysconfig/certbot
PRE_HOOK="--pre-hook 'systemctl stop httpd'"
POST_HOOK="--post-hook 'systemctl start httpd'"
RENEW_HOOK=""
CERTBOT_ARGS=""
EOF

sed -i "s/#SSLEngine/SSLEngine/" "/etc/httpd/conf.d/${INTERMEDIATE_FQDN}.conf"
sed -i "s/#Redirect/Redirect/" "/etc/httpd/conf.d/${INTERMEDIATE_FQDN}.conf"

sed -i "s|#SSLCertificateFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/cert.pem|SSLCertificateFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/cert.pem|" "/etc/httpd/conf.d/${INTERMEDIATE_FQDN}.conf"
sed -i "s|#SSLCertificateKeyFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/privkey.pem|SSLCertificateKeyFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/privkey.pem|" "/etc/httpd/conf.d/${INTERMEDIATE_FQDN}.conf"
sed -i "s|#SSLCertificateChainFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/chain.pem|SSLCertificateChainFile /etc/letsencrypt/live/${INTERMEDIATE_FQDN}/chain.pem|" "/etc/httpd/conf.d/${INTERMEDIATE_FQDN}.conf"

systemctl start httpd

###############################################################################
# CRON
###############################################################################

install -m 600 etc/vpn-provisioning "/etc/vpn-provisioning"

sed -i "s/vpn.example/${INTERMEDIATE_FQDN}/" "/etc/vpn-provisioning"
sed -i "s/{vpnUrl}/${VPN_URL_SED}/" "/etc/vpn-provisioning"
sed -i "s/{adminApiToken}/${ADMIN_API_TOKEN}/" "/etc/vpn-provisioning"
sed -i "s/{tenantId}/${TENANT_ID}/" "/etc/vpn-provisioning"
sed -i "s/{applicationId}/${APPLICATION_ID}/" "/etc/vpn-provisioning"
sed -i "s/{secretToken}/${SECRET_TOKEN}/" "/etc/vpn-provisioning"

mkdir -p "/usr/libexec/vpn-provisioning"
install -m 755 ./revokeVpnConfigs "/usr/libexec/vpn-provisioning/revokeVpnConfigs"
mkdir -p -m 700 "/var/lib/vpn-provisioning"
touch "/var/lib/vpn-provisioning/localDeviceIds.txt"
chown -R apache:apache "/var/lib/vpn-provisioning"
chcon -R -h -t httpd_sys_rw_content_t "/var/lib/vpn-provisioning"

cp ./eduVpnProvisioning /etc/cron.d/eduVpnProvisioning

###############################################################################
# NOTES
###############################################################################

echo "Please visit:"
echo "  https://${INTERMEDIATE_FQDN}/management_script/"
echo "to generate scripts for macOS and Windows eduVPN profile deployments."
