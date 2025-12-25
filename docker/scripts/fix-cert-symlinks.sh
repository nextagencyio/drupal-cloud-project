#!/bin/sh
# Fix certificate symlinks for nginx-proxy
# This script runs in the letsencrypt container on startup

CERTS_DIR="/etc/nginx/certs"

# Wait for certificates to exist
sleep 10

# Function to create symlinks for a domain
create_cert_symlinks() {
    local domain="$1"
    local domain_dir="${CERTS_DIR}/${domain}"

    if [ -d "$domain_dir" ] && [ -f "$domain_dir/fullchain.pem" ] && [ -f "$domain_dir/key.pem" ]; then
        echo "Creating certificate symlinks for $domain"

        # Create copies (not symlinks) because docker-gen template checks file existence
        cp -f "$domain_dir/fullchain.pem" "${CERTS_DIR}/${domain}.crt"
        cp -f "$domain_dir/key.pem" "${CERTS_DIR}/${domain}.key"

        # Create copies for wildcard domain
        cp -f "$domain_dir/fullchain.pem" "${CERTS_DIR}/*.${domain}.crt"
        cp -f "$domain_dir/key.pem" "${CERTS_DIR}/*.${domain}.key"

        # Set correct permissions
        chmod 644 "${CERTS_DIR}/${domain}.crt" "${CERTS_DIR}/*.${domain}.crt"
        chmod 600 "${CERTS_DIR}/${domain}.key" "${CERTS_DIR}/*.${domain}.key"

        echo "Certificate files created for $domain"
    fi
}

# Loop through all domain directories in certs
for domain_dir in ${CERTS_DIR}/*/; do
    if [ -d "$domain_dir" ]; then
        domain=$(basename "$domain_dir")
        create_cert_symlinks "$domain"
    fi
done

echo "Certificate symlink fix complete"
