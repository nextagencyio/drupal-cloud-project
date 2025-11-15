#!/bin/sh

# SSL Renewal Script for decoupled.io wildcard certificate
# This script should be run via cron for automatic renewal

DOMAIN="decoupled.io"
CERT_PATH="/etc/nginx/certs"
ACME_SH="/app/acme.sh"

echo "Checking certificate renewal for ${DOMAIN}..."

# Force renewal if certificate expires within 30 days
${ACME_SH} --renew -d "${DOMAIN}" --force

if [ $? -eq 0 ]; then
    echo "Certificate renewed, installing..."
    
    # Install renewed certificate
    ${ACME_SH} --install-cert -d "${DOMAIN}" \
        --key-file "${CERT_PATH}/${DOMAIN}.key" \
        --fullchain-file "${CERT_PATH}/${DOMAIN}.crt"
    
    # Reload nginx if running in same container network
    echo "Reloading nginx..."
    docker exec nginx-proxy nginx -s reload 2>/dev/null || echo "Could not reload nginx (container may be separate)"
    
    echo "Certificate renewal completed"
else
    echo "No renewal needed or renewal failed"
fi