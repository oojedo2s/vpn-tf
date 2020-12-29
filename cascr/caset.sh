#!/bin/bash

e="echo -e"
bg="\e[1;34m"
ed="\e[0m"
user=$(whoami)
sudo apt update
sudo apt install easy-rsa python3-gevent python3-flask python3-werkzeug -y

openssl req -newkey rsa:4096 -nodes -keyout prkey.pem -x509 -days 36500 -out sercert.pem -subj "/C=DE/ST=NRW/L=Koeln/O=Tunes/OU=IT/CN=www.tunes.com/emailAddress=tunsgcpaceuser@gmail.com"

mkdir /home/$user/easy-rsa
ln -s /usr/share/easy-rsa/* /home/$user/easy-rsa/

chmod 700 /home/$user/easy-rsa

cd /home/$user/easy-rsa && source /home/$user/easy-rsa/easyrsa init-pki
sed -i '/RANDFILE/d' /home/$user/easy-rsa/pki/openssl-easyrsa.cnf

touch /home/$user/easy-rsa/vars
$e "set_var EASYRSA_REQ_COUNTRY    \"DE\"" > /home/$user/easy-rsa/vars
$e "set_var EASYRSA_REQ_PROVINCE   \"NRW\"" > /home/$user/easy-rsa/vars
$e "set_var EASYRSA_REQ_CITY       \"Koeln\"" > /home/$user/easy-rsa/vars
$e "set_var EASYRSA_REQ_ORG        \"Tunes\"" > /home/$user/easy-rsa/vars
$e "set_var EASYRSA_REQ_EMAIL      \"tunsgcpaceuser@gmail.com\"" > /home/$user/easy-rsa/vars
$e "set_var EASYRSA_REQ_OU         \"Personal\"" > /home/$user/easy-rsa/vars
$e "set_var EASYRSA_ALGO           \"ec\"" > /home/$user/easy-rsa/vars
$e "set_var EASYRSA_DIGEST         \"sha512\"" > /home/$user/easy-rsa/vars

# Creates CA certificate file and key at /home/$user/easy-rsa/pki/ca.crt
cd /home/$user/easy-rsa && source /home/$user/easy-rsa/easyrsa build-ca nopass