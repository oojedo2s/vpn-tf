#!/bin/bash

e="echo -e"
bg="\e[1;34m"
bg2="\e[1;31m"
ed="\e[0m"
user=$(whoami)
curl="sudo curl -s"
sed="sudo sed -i -e"
sh="sudo sh -c"
pub_int=$(ip route list default | awk -F ' ' '{print $5}')
pub_int_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
vars="/home/$user/easy-rsa/vars"

$e "$bg Enter CA server ip address:  $ed"
read ip

sudo apt update
sudo apt install openvpn easy-rsa curl jq

if [[ -f "$vars" ]]; then
    $e "$bg Easy RSA has been setup $ed"
else
    mkdir /home/$user/easy-rsa
    ln -s /usr/share/easy-rsa/* /home/$user/easy-rsa/

    sudo chown $user /home/$user/easy-rsa
    # Make file executable
    chmod 700 /home/$user/easy-rsa

    touch $vars
    $e "set_var EASYRSA_ALGO \"ec\"" > $vars
    $e "set_var EASYRSA_DIGEST \"sha512\"" > $vars

    #Create directory to store client certificates and files
    mkdir -p /home/$user/client-configs/keys
    chmod -R 700 /home/$user/client-configs
fi

# Function to configure tls-crypt used for TLS certificate obfuscation during initial connection
tls_crypt() {
    cd /home/$user/easy-rsa && openvpn --genkey --secret ta.key
    sudo cp ta.key /etc/openvpn/server
    cp /home/$user/easy-rsa/ta-key /home/$user/client-configs/keys
}
tls_crypt

# Function to generate server certificate
serv_cert() {

    source /home/$user/easy-rsa/easyrsa init-pki
    source /home/$user/easy-rsa/easyrsa gen-req server nopass
    sudo cp /home/$user/easy-rsa/pki/private/server.key /etc/openvpn/server/
    
    sername="server"
    reqserv="/home/$user/easy-rsa/pki/reqs/$sername'.req'"
    servcert="/etc/openvpn/server/server.crt"

    if [[ -f "$servcert" ]]; then
        $e "$bg There is an existing server certificate $ed"
    else
        servcertreq="$curl -F "file=@$reqserv" https://$ip/sercert $key"

        #import CA certificate into the OS certificate store
        cacertcurl=$($servcertreq | jq -r '.cacert' > "/tmp/ca.crt")
        sudo cp /tmp/ca.crt /usr/local/share/ca-certificates/
        sudo update-ca-certificates
        
        #import server certificate
        servcertcurl=$($servcertreq | jq -r '.cert' > "/tmp/server.crt" )
        sudo cp /tmp/{ca.crt,server.crt} /etc/openvpn/server

        #copy CA cert to client folder for configuration and files 
        sudo cp /tmp/ca.crt /home/$user/client-configs/keys/
    fi
}
serv_cert

# Function to generate/revoke client certificate
client_cert() {
    $e "$bg Enter 'generate' to generate cert or 'revoke' to revoke cert: $ed"
    read option
    if [[ -z $option ]]; then
        $e "$bg2 Option cannot be empty $ed"
        client_cert
    fi
    $e "$bg Enter client name of certificate request: $ed"
    read client_name
    
    if [[ $option != generate ]] || [[ $option != revoke ]]; then
        $e "$bg2 Option must be either 'generate' or 'revoke' $ed"
        client_cert

    elif [[ $option == generate ]]; then 
        source /home/$user/easy-rsa/easyrsa gen-req client_name nopass
        cp /home/$user/easy-rsa/pki/private/$client_name".key" /home/$user/client-configs/keys
        reqclient="/home/$user/easy-rsa/pki/reqs/$client_name'.req'"
        clientcertreq="$curl -F "file=@$reqclient" https://$ip/clientcert $key"

        #import server certificate
        clientcertcurl=$($clientcertreq | jq -r '.cert' > "/tmp/$client_name'.crt'" )
        sudo cp /tmp/$client_name'.crt' /home/$user/client-configs/keys/
    
        sudo chown $user.$user /home/$user/client-configs/keys/*

    elif [[ $option == revoke ]]; then
        servcertrev="$curl -F "file=@$client_name" https://$ip/revokecert $key"
    fi
}
client_cert

# Configure OpenVPN
sudo cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz /etc/openvpn/server/
sudo gunzip /etc/openvpn/server/server.conf.gz

# Edit Server config file
# Change HMAC
$sed 's/tls-auth ta.key 0/tls-crypt ta.key/g' /etc/openvpn/server/server.conf
#Change encryption cipher
$sed 's/cipher AES-256-CBC/cipher AES-256-GCM/g' /etc/openvpn/server/server.conf
# Set HMAC message digest algorithm as SHA 256
$sh "echo 'auth SHA256' >> /etc/openvpn/server/server.conf"
# Remove Diffie Hellman since ellipttic curve is used instead
$sed 's/dh dh2048.pem/dh none/g' /etc/openvpn/server/server.conf
#Enable OpenVPN to run without privileges
$sed 's/;user nobody/user nobody/g' /etc/openvpn/server/server.conf
$sed 's/;group nogroup/group nogroup/g' /etc/openvpn/server/server.conf
#Push DNS to redirect all traffic through VPN
$sed 's/;push "redirect-gateway def1 bypass-dhcp"/push "redirect-gateway def1 bypass-dhcp"/g' /etc/openvpn/server/server.conf
#Use free OpenDNS resolvers
$sed 's/;push "dhcp-option DNS 208.67.222.222"/push "dhcp-option DNS 208.67.222.222"/g' /etc/openvpn/server/server.conf
$sed 's/;push "dhcp-option DNS 208.67.220.220"/push "dhcp-option DNS 208.67.220.220"/g' /etc/openvpn/server/server.conf
#Adjust default IP forwarding 
$sh "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf"

# Enable firewall
sudo ufw enable

# Edit firewall to add masquerading
cat <<EOF >/etc/ufw/before.rules
# START OPENVPN NAT RULES
*nat
:POSTROUTING ACCEPT [0:0]
# Allow traffic from OpenVPN client to public interface
-A POSTROUTING -s 10.8.0.0/8 -o $pub_int -j MASQUERADE
COMMIT
# END OPENVPN NAT RULES
EOF

# Enable UFW to forward packets by default
$sed 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/openvpn/server/server.conf

# Allow traffic to OpenVPN and re-enable firewall
sudo ufw allow 1194/udp
sudo ufw disable
sudo ufw enable

# Enable OpenVPN to start up at boot
sudo systemctl -f enable openvpn-server@server.service

# Start OpenVPN and check status
sudo systemctl start openvpn-server@server.service
sudo systemctl status openvpn-server@server.service

# Create folder to store client config files & set up base conf
mkdir -p /home/$user/client-configs/files
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf /home/$user/client-configs/base.conf
# Set remote Public IP of OpenVPN server
$sed "s/remote my-server-1 1194/remote $pub_int_ip 1194/g" /home/$user/client-configs/base.conf
# Remove privileges (non-Windows only)
$sed 's/;user nobody/user nobody/g' /home/$user/client-configs/base.conf
$sed 's/;group nogroup/group nogroup/g' /home/$user/client-configs/base.conf
# Enable CA, cert and key 
$sed 's/;ca ca.crt/ca ca.crt/g' /home/$user/client-configs/base.conf
$sed 's/;cert client.crt/cert client.crt/g' /home/$user/client-configs/base.conf
$sed 's/;key client.key/key client.key/g' /home/$user/client-configs/base.conf
# Enable tls-auth
$sed 's/;tls-auth ta.key 1/tls-auth ta.key 1/g' /home/$user/client-configs/base.conf
# Add cipher and auth
$sed "s/cipher AES-256-CBC/cipher AES-256-GCM/g" > /home/$user/client-configs/base.conf
$e "auth SHA256" > /home/$user/client-configs/base.conf
# Set key-direction to 1
$e "key-direction 1" > /home/$user/client-configs/base.conf


# To generate client .ovpn files as quickly as possible
# usage: 1. make script executable
#        2. run script followed by common name of client e.g ./ovpn.sh clienta
KEY_DIR=/home/$user/client-configs/keys
OUTPUT_DIR=/home/$user/client-configs/files
BASE_CONFIG=/home/$user/client-configs/base.conf

cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${KEY_DIR}/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    ${KEY_DIR}/${1}.key \
    <(echo -e '</key>\n<tls-crypt>') \
    ${KEY_DIR}/ta.key \
    <(echo -e '</tls-crypt>') \
    > ${OUTPUT_DIR}/${1}.ovpn