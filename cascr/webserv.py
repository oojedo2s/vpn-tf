from gevent.pywsgi import WSGIServer
from flask import Flask, request, jsonify
from werkzeug.exceptions import HTTPException
import subprocess
import os
import socket
import getpass

# Declaration of parameters
#username = getpass.getuser()
username = os.getlogin()
print("username is", username)
upload_folder_host = '/home/{}/easy-rsa/pki/issued'.format(username)
upload_folder_ca = '/home/{}/easy-rsa/pki'.format(username)
upload_folder_rsa = '/home/{}/easy-rsa'.format(username)
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


#@app.errorhandler(Exception)
#def handle_exception(error):
    # Handle HTTP errors.
 #   if isinstance(error, HTTPException):
  #      return error

    # Handle non-HTTP errors
   # return 'Sorry, Internal Server Error Occurred!!! Contact your administrator!\n', 500
    # return error, 500


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
        import_key = ("cd " + upload_folder_rsa + " && ./easyrsa import-req " + 
                    temp_folder + '/' + filename + ' ' + filename_req)
        imprt = subprocess.Popen(import_key, shell=True, stdout=subprocess.PIPE,
                                    universal_newlines=True).communicate()[0].strip()
        sign_key = ("cd " + upload_folder_rsa + " && (printf 'yes' | ./easyrsa sign-req server " + 
                    filename_req + ")")
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
        import_key = ("cd " + upload_folder_rsa + " && ./easyrsa import-req " + 
                    temp_folder + '/' + filename + ' ' + filename_req)
        imprt = subprocess.Popen(import_key, shell=True, stdout=subprocess.PIPE,
                                    universal_newlines=True).communicate()[0].strip()
        sign_key = ("cd " + upload_folder_rsa +  " && (printf 'yes' | ./easyrsa sign-req client " + 
                    filename_req + ")")
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
    revoke_crt = ("cd " + upload_folder_rsa + " && (printf 'yes' | ./easyrsa revoke " + 
                filename_req + ")")
                

if __name__ == "__main__":
    http_server = WSGIServer((ip, 443), app,
                             keyfile='./prkey.pem', certfile='./sercert.pem')
    http_server.serve_forever()
