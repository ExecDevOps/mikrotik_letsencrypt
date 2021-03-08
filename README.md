Mikrotik and LetsEncrypt
========================

Certificates from LetsEncrypt are great and Mikrotik ROS can use them for services but ROS can not renew them. Here is a solution that imports certificate files from an extern repository and recreates the certificate in ROS and updates ROS services so they can use the updated certificate.

It all starts with an external Linux server, with Certbot, that updates LetsEncrypt certificate for a domain. Upon successful uppdate Certbot executes a post-hook deploy script that copies the certificate file and key to a repository from which  Mikrotik to retrieves the files from. In order to do so Mikrotik needs to have passwordless login to an account that has access to the location of the certificate files. The account will be "mikrotik" having "IRBaboon" as password for regular login.

Start with creating the "mikrotik" account on the Linux server:

  # adduser mikrotik
  
Log in to this new account:

  # sudo -iu mikrotik
  
Create a private/public certificate/key combination, this will create the necessary ~/.ssh directory with correct permissions and store the certificate files in ~/.ssh/id_rsa resp. ~/.ssh/id_rsa.pub. NOTE! do not supply a password, i.e. use an empty password:

  # ssh-keygen -t RSA -m PEM -N ""
  
Add the public key to the list of trusted public keys for login to this account:

  # cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys



Certbot
=======

Install Certbot:

  # apt install certbot

Create a wildcard certificate for "*.acme.com", this requires adding a TXT record to the DNS server for the acme.com domain. Certbot will provide instructions as to what the record needs to look like, it will be something like "_acme-challenge.acme.com. 300 IN TXT "gfj9Xq...Rg85nM":

  # certbot certonly --preferred-challenges=dns --manual --hsts --staple-ocsp --email support@acme.com -d *.acme.com --server https://acme-v02.api.letsencrypt.org/directory

Create a deploy script for Certbot to run every time the certificate gets updated. The script will create a repository (directory) that only the "mikrotik" account we created earlier has access to:

  # nano /etc/letsencrypt/renewal-hooks/deploy/0001-mikrotik-certbot-deploy.sh

	#!/bin/sh

	set -e

	MIKROTIK_DIR="/etc/mikrotik"

	# create a directory to store certs if it does not exists
	if [ ! -d "$MIKROTIK_DIR/certs" ]; then
	    mkdir -p $MIKROTIK_DIR/certs
	    chown -R mikrotik:mikrotik $MIKROTIK_DIR/
	    chmod -R 700 $MIKROTIK_DIR/
	    #chmod -R go= $MIKROTIK_DIR/
	fi

	# Copy certificate and key to cert storage
	for domain in $RENEWED_DOMAINS; do
	    case $domain in
		acme.com)
		    # Make sure the certificate and private key files are
		    # never world readable, even just for an instant while
		    # we're copying them into daemon_cert_root.
		    umask 077

		    cp "$RENEWED_LINEAGE/fullchain.pem" "$MIKROTIK_DIR/certs/$domain.crt"
		    cp "$RENEWED_LINEAGE/privkey.pem" "$MIKROTIK_DIR/certs/$domain.key"

		    # Apply the proper file ownership and permissions for
		    # the daemon to read its certificate and key.
		    chown mikrotik "$MIKROTIK_DIR/certs/$domain.crt" "$MIKROTIK_DIR/certs/$domain.key"
		    chmod 400 "$MIKROTIK_DIR/certs/$domain.crt" "$MIKROTIK_DIR/certs/$domain.key"
		   ;;
	    esac
	done

Apply correct rights and make the script executable:

	# chmod 744 /etc/letsencrypt/renewal-hooks/deploy/0001-mikrotik-certbot-deploy.sh

Add the script to Certbot's post-hook for this domain:

	# nano /etc/letsencrypt/renewal/acme.com.conf

	[...]
	post_hook = /etc/letsencrypt/renewal-hooks/deploy/0001-mikrotik-certbot-deploy.sh
	[...]


Renew the certificate and make sure it gets copied to the repository:

	# ls -l /etc/mikrotik/certs



Mikrotik
========

Från Mikrotik, för inloggning från Mikrotik till fjärrserver:

	/tool fetch url="sftp://10.10.10.111/home/mikrotik/id_rsa" user=mikrotik password="IRBaboon" dst-path=id_rsa 
	/tool fetch url="sftp://10.10.10.111/home/mikrotik/id_rsa.pub" user=mikrotik password="IRBaboon" dst-path=id_rsa.pub 


Importera dom så att användaren "admin" kan använda sig av privata nyckeln för autentisering av 
inloggning till kontot "mikrotik" på servern:

	/user ssh-keys private import user=admin private-key-file=id_rsa public-key-file=id_rsa.pub passphrase=""


Testa att från Mikrotik logga in till kontot "mikrotik" på servern 10.10.222.250 utan lösenord:

	/system ssh 10.10.222.250 user=mikrotik
