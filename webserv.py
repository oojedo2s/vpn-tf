from gevent.pywsgi import WSGIServer
from flask import Flask, request, jsonify
from werkzeug.exceptions import HTTPException
import subprocess
import os
import socket
import getpass

# Declaration of parameters
username = getpass.getuser()
upload_folder_host = '/home/{}/easy-rsa/pki/issued'.format(username)
upload_folder_ca = '/home/{}/easy-rsa/pki'.format(username)
temp_folder = '/tmp'
app = Flask(__name__)
app.debug = True
app.config['upload_folder_host'] = upload_folder_host
app.config['upload_folder_ca'] = upload_folder_ca
app.config['temp_folder'] = temp_folder


# Obtain IP address of web server
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as soc:
    try:
        soc.connect(('10.255.255.255', 1))
        ip = soc.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
print("IP address of web server is", ip)


# Function to handle custom HTTP errors 404 and 500
@app.errorhandler(404)
def resource_not_found(error):
    return 'Resource Not Found!!! Contact your administrator!\n', 404


@app.errorhandler(Exception)
def handle_exception(error):
    # Handle HTTP errors.
    if isinstance(error, HTTPException):
        return error

    # Handle non-HTTP errors
    return 'Sorry, Internal Server Error Occurred!!! Contact your administrator!\n', 500
    # return error, 500


# Function to sign client certificate
# First checks if request is from a client or host and if it contains a public key.
# Next it copies key into a folder and uses CA private key to sign and generate client certificate.
# Finally, it responds to client with its certificate and the CA's public key for verification
def sign_cert(client, cakey):
    parm1 = ''
    parm2 = " -n "
    if client == "host":
        parm1 = "-h"
        parm2 = ''
        clientqr = ''
    file = request.files['file']
    filename = file.filename
    file.save(os.path.join(app.config['upload_folder_' + client], filename))
    casignkey = upload_folder_ca + "/ca_" + client
    caverikey = upload_folder_ca + "/" + cakey
    if os.path.isfile(casignkey) and os.path.isfile(caverikey):
        viewkey = (keygen + " -lf " + upload_folder_ca + "/" + client + 's' +
                   "/" + filename + " | awk '{print $3}' | awk -F '@' '{print $1}'")
        view = subprocess.Popen(viewkey, shell=True, stdout=subprocess.PIPE,
                                universal_newlines=True).communicate()[0].strip()
        signkey = (keygen + " -q -s " + casignkey + " " + parm1 + " -V +52w -I " +
                   view + parm2 + (view if client == "user" else "") + " " + upload_folder_ca + "/" + client + 's' + "/" + filename)
        sign = subprocess.Popen(signkey, shell=True,
                                stdout=subprocess.PIPE).communicate()[0]
        certfilename = filename[:-4] + "-cert.pub"

        if client == "user":
            with open(upload_folder_ca + "/" + client + "s/" + view + "_gauth") as client_qr:
                clientqr = client_qr.read().rstrip('\n')
        with open(upload_folder_ca + "/" + client + "s/" + certfilename) as client_cert:
            clientcert = client_cert.read().rstrip('\n')
        with open(upload_folder_ca + "/" + cakey) as cafile:
            ca = cafile.read().rstrip('\n')
        cert = jsonify({'cert': clientcert, 'qr': clientqr,
                        'cakey': ca, 'status': 200})
        return cert
    else:
        return resource_not_found(404)


# Homepage endpoint
@app.route('/', methods=['GET'])
def index():
    return "Welcome to Pix World!!!"


# Endpoint called from Host client for QR code
# Checks POST request for file and saves file in a folder
@app.route('/sercert', methods=['POST'])
def server_cert():
    file = request.files['file']
    filename = file.filename
    filename_req = filename[:-4]
    file.save(os.path.join(app.config['temp_folder'], filename))
    if os.path.isfile(upload_folder_ca + "/ca.crt"):
        import_key = (source '/home/'+username+'/easy-rsa/easyrsa import-req ' + 
                    temp_folder + '/' + filename + ' ' + filename_req)
        imprt = subprocess.Popen(import_key, shell=True, stdout=subprocess.PIPE,
                                    universal_newlines=True).communicate()[0].strip()
        sign_key = (yes + '|' + (source '/home/'+username+'/easy-rsa/easyrsa sign-req ' + 
                    'server ' + filename_req))
        #sign_key = (spawn (source '/home/'+username+'/easy-rsa/easyrsa sign-req ' + 
        #            filename_req + ' ' + filename_req) && expect + " Confirm request details:" 
        #            && send + " yes")
        sign = subprocess.Popen(sign_key, shell=True, stdout=subprocess.PIPE,
                                    universal_newlines=True).communicate()[0].strip()
        with open(upload_folder_ca + "/ca.crt") as cafile:
            ca = cafile.read().rstrip('\n')
        with open(upload_folder_host + "/" + filename_req + ".crt") as serverfile:
            sercert = serverfile.read().rstrip('\n')
        cert = jsonify({'cert': sercert, 'cacert': ca})
        return cert
    else:
        return resource_not_found(404)


@app.route('/clientcert', methods=['POST'])
def client_cert():
    file = request.files['file']
    filename = file.filename
    filename_req = filename[:-4]
    file.save(os.path.join(app.config['temp_folder'], filename))
    if os.path.isfile(upload_folder_ca + "/ca.crt"):
        import_key = (source '/home/'+username+'/easy-rsa/easyrsa import-req ' + 
                    temp_folder + '/' + filename + ' ' + filename_req)
        imprt = subprocess.Popen(import_key, shell=True, stdout=subprocess.PIPE,
                                    universal_newlines=True).communicate()[0].strip()
        sign_key = (yes + '|' + (source '/home/'+username+'/easy-rsa/easyrsa sign-req ' + 
                    'client ' + filename_req))
        #sign_key = (spawn (source '/home/'+username+'/easy-rsa/easyrsa sign-req ' + 
        #            filename_req + ' ' + filename_req) && expect + " Confirm request details:" 
        #            && send + " yes")
        sign = subprocess.Popen(sign_key, shell=True, stdout=subprocess.PIPE,
                                    universal_newlines=True).communicate()[0].strip()
        with open(upload_folder_host + "/" + filename_req + ".crt") as clientfile:
            clientcert = clientfile.read().rstrip('\n')
        cert = jsonify({'cert': clientcert})
        return cert
    else:
        return resource_not_found(404)


@app.route('/revokecert', methods=['POST'])
def revoke_cert():
    file = request.files['file']
    filename = file.filename
    filename_req = filename[:-4]
    revoke_crt = (yes + '|' + (source '/home/'+username+'/easy-rsa/easyrsa revoke ' + filename_req))

if __name__ == "__main__":
    http_server = WSGIServer((ip, 443), app,
                             keyfile='./prkey.pem', certfile='./sercert.pem')
    http_server.serve_forever()
