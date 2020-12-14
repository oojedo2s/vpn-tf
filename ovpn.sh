#!/bin/bash

e="echo -e"
bg="\e[1;34m"
bg2="\e[1;31m"
ed="\e[0m"
user=$(whoami)
curl="sudo curl -s"
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
    chmod 700 /home/$user/easy-rsa

    touch $vars
    echo -e "set_var EASYRSA_ALGO \"ec\"" > $vars
    echo -e "set_var EASYRSA_DIGEST \"sha512\"" > $vars

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


