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

Log in to Mikrotik ROS "admin" user and fetch the certificate files from the Linux server using password:

	/tool fetch url="sftp://10.10.10.111/home/mikrotik/id_rsa" user=mikrotik password="IRBaboon" dst-path=id_rsa 
	/tool fetch url="sftp://10.10.10.111/home/mikrotik/id_rsa.pub" user=mikrotik password="IRBaboon" dst-path=id_rsa.pub 

Import the certificate's private key to Mikrotik's "admin" user so "admin" can use it for login to the "mikrotik" user account on the Linux server:

	/user ssh-keys private import user=admin private-key-file=id_rsa public-key-file=id_rsa.pub passphrase=""

Test login to the Linux server's "mikrotik" user account using the certificate and no password :

	/system ssh 10.10.10.111 user=mikrotik



Mikrotik transfer and import of certificate
===========================================

Setup e-mail settings in ROS to send mail via i.e. Office365:

	/tool e-mail
	set address=smtp.office365.com from=servicenotification@acme.com password=IRBaboonSmells port=587 start-tls=yes user=servicenotification@acme.com

Create schedule in ROS for for transport and import of certificate:

	/system scheduler 
	add interval=1d name="Uppdate certificate" on-event=script_Letsencrypt policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive start-date=may/13/2016 start-time=02:30:00

Create help script "fn_date_to_days" containing subroutine to calculate the number of days since 0000-01-01. It takes a date in the format of ":put [/system clock get date]" ("mar/05/2021") as input and returns the number of days:

	:local iMonthID   {"jan"=1; "feb"=2; "mar"=3; "apr"=4; "may"=5; "jun"=6; "jul"=7; "aug"=8; "sep"=9; "oct"=10; "nov"=11; "dec"=12}
	:local iMonthDays {31; 28; 31; 30; 31; 30; 31; 31; 30; 31; 30; 31}

	:local iYYYY [:tonum [:pick $sDate 7 11]]
	:local iMM   [:tonum ($iMonthID->([:pick $sDate 0 3]))]
	:local iDD   [:tonum [:pick $sDate 4  6]]

	:local iDays ($iYYYY * 365 + $iDD)

	# Get number of days since Jan 1 for current year, with consideration to being a leapyear
	:for i from=1 to=($iMM - 1) step=1 do={ 
	    :if ($iMM = 2  &&  (($iYYYY & 3 = 0  &&  ($iYYYY / 100100 != $iYYYY))  ||  $iYYYY / 400400 = $iYYYY) ) do={ 
	      :set iDayis ($iDays + 1)
	    }

	    :set iDays ($iDays + [:pick $iMonthDays ($i - 1)]) 
	}

	:return $iDays

Create the main script "script_Letsencrypt", adjust the variables at the beginning to suit your settings, i.e. server address and repository location. At the end of the script add Mikrotik services that are using the certificate, they need to re-assign the certificate as it gets renewed:

	:local sServer "10.10.10.111"
	:local sLogin  "mikrotik"
	:local sPath   "/etc/mikrotik/certs/"
	:local sHost   "*"
	:local sDomain "acme.com"
	:local sMailTo "execdevnull@acme.com"


	:local sIdentity [/system identity get name]
	:local sCN       "$sHost.$sDomain"


	# Import script containing external function that calculates number of days
	:local fnDateToDays [:parse [/system script get fn_date_to_days source]]


	:log warn ("Certificate update for " . $sCN . " starting") 


	# Delete leftovers
	:if ([/file find name="$sDomain.crt"] != "") do={
	    /file remove "$sDomain.crt"
	}

	:if ([/file find name="$sDomain.key"] != "") do={
	    /file remove "$sDomain.key"
	}


	# Fetch certificate and key from server
	/tool fetch url="sftp://$sServer/$sPath/$sDomain.crt" user=$sLogin dst-path="$sDomain.crt"
	/tool fetch url="sftp://$sServer/$sPath/$sDomain.key" user=$sLogin dst-path="$sDomain.key"

	:delay 1s

	# Import if fetch was successful
	:if (([/file find name="$sDomain.crt"] != "")  &&  ([/file find name="$sDomain.key"] != "")) do={

	    # Get current certificate fingerprint
	    :local sFingerNow ""
	    :local sFingerNew ""

	    :if ([/certificate find where common-name=$sCN]) do={
		:set sFingerNow [/certificate get [/certificate find where common-name=$sCN] fingerprint]
	    }


	    :log warn ("Replacing certificate for " . $sCN) 

	    # Delete current certificate
	    /certificate remove [find name="$sDomain.crt_0"]
	    /certificate remove [find name="$sDomain.crt_1"]

	    :delay 1s

	    # Import new certificate and key
	    /certificate import file-name="$sDomain.crt" passphrase=""
	    /certificate import file-name="$sDomain.key" passphrase=""

	    :delay 1s

	    # Remove files not needed anymore
	    /file remove "$sDomain.crt"
	    /file remove "$sDomain.key"


	    # Compare new fingerprint with old
	    :set sFingerNew [/certificate get [/certificate find where common-name=$sCN] fingerprint]
	    :if ($sFingerNew != $sFingerNow) do={
		:log warn ("Got new certificate for " . $sCN) 
		:log warn ("Now: " . $sFingerNow)
		:log warn ("New: " . $sFingerNew)

		/tool e-mail send to=$sMailTo subject=($sCN . " certificate updated") body=("Certificate for " . $sCN . " updated at " . $sIdentity . " from sftp://" . $sServer . $sPath . $sDomain)
	    }


	    # Update services with the new certificate
	    :log warn ("Replacing certificate for " . $sCN . " services")

	    :local sCertName [/certificate get [/certificate find where common-name=$sCN] name]

	    /ip hotspot profile set [find name="server_Test"] ssl-certificate=$sCertName
	    /interface sstp-server server set certificate=$sCertName


	    :log warn ("Certificate update for " . $sCN . " done")
	} else={
	    :log error ("Failed to fetch certificate or key for " . $sCN)

	    /tool e-mail send to=$sMailTo subject=($sIdentity . " certificate problem") body=($sIdentity . " could not fetch certificate for " . $sCN . " from sftp://" . $sServer . $sPath . $sDomain . ". Check that the server is available for login to the '" . $sLogin . "' account and that certificate files are available at " . $sPath . $sDomain)
	}


	# Compare certificate expire date with todays date, send message if less than twoo weeks remains
	:local sDateExpire [:pick [/certificate get [/certificate find where common-name=$sCN] invalid-after] 0 11]
	:local sDateToday  [/system clock get date ]
	:local iDaysLeft   ([$fnDateToDays sDate=$sDateExpire] - [$fnDateToDays sDate=$sToday])

	:if ($iDaysLeft < 14) do={
	    :log error ("Certificate for " . $sCN . " expires in " . $iDaysLeft . " days!!!") 

	    /tool e-mail send to=$sMailTo subject=($sIdentity . " certificate problem") body=("Certificate for " . $sCN . " expires in " . $iDaysLeft . " day(s) and needs updating. Transfer from sftp://" . $sServer . "/" . $sPath . "/" . $sDomain . " does not result in renewed certificate " . $sDomain.crt_0 . ". Check that certbot on " . $sServer . " is renewing correctly!")
	}


	:log warn ("Certificate update finished") 

That's it! Mikrotik should now fetch certificate files from the repository on the Certbot server and activate services with it.
