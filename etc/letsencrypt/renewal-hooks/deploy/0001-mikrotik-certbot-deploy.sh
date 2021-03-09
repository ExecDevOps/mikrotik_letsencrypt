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
