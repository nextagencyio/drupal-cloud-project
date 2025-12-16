#!/bin/sh

# SSL Setup Script for wildcard certificate
# This script runs on container startup to ensure certificates exist

# Use DOMAIN_SUFFIX from environment, fallback to dcloud.dev
DOMAIN="${DOMAIN_SUFFIX:-dcloud.dev}"
WILDCARD_DOMAIN="*.${DOMAIN}"
CERT_PATH="/etc/nginx/certs"
ACME_SH="/app/acme.sh"

echo "Starting SSL setup for ${DOMAIN} and ${WILDCARD_DOMAIN}..."

# Check if certificates already exist and are valid
if [ -f "${CERT_PATH}/${DOMAIN}.crt" ] && [ -f "${CERT_PATH}/${DOMAIN}.key" ]; then
    echo "Certificate files already exist, checking validity..."
    
    # Check if certificate expires within 30 days
    if openssl x509 -checkend 2592000 -noout -in "${CERT_PATH}/${DOMAIN}.crt" >/dev/null 2>&1; then
        echo "Certificate is valid for more than 30 days, skipping setup"
        exit 0
    else
        echo "Certificate expires within 30 days, renewing..."
    fi
fi

# Register account if needed
if [ ! -f "/root/.acme.sh/account.conf" ]; then
    echo "Registering acme.sh account with Let's Encrypt..."
    ${ACME_SH} --register-account -m admin@${DOMAIN} --server https://acme-v02.api.letsencrypt.org/directory
fi

# Issue certificate for both apex and wildcard domains
echo "Issuing certificate for ${DOMAIN} and ${WILDCARD_DOMAIN}..."
${ACME_SH} --issue \
    -d "${DOMAIN}" \
    -d "${WILDCARD_DOMAIN}" \
    --dns dns_cf \
    --server https://acme-v02.api.letsencrypt.org/directory

# Install certificate
if [ $? -eq 0 ]; then
    echo "Installing certificate..."
    ${ACME_SH} --install-cert -d "${DOMAIN}" \
        --key-file "${CERT_PATH}/${DOMAIN}.key" \
        --fullchain-file "${CERT_PATH}/${DOMAIN}.crt"

    # Create default certificate symlinks for nginx-proxy fallback
    echo "Creating default certificate symlinks..."
    ln -sf "${DOMAIN}.crt" "${CERT_PATH}/default.crt"
    ln -sf "${DOMAIN}.key" "${CERT_PATH}/default.key"

    echo "SSL setup completed successfully"
else
    echo "Certificate issuance failed"
    exit 1
fi