# mikrotik_letsencrypt

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
  
