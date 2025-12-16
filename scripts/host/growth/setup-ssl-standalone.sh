#!/bin/bash
#
# Setup Let's Encrypt SSL for standalone Drupal droplet.
# Usage: ./setup-ssl-standalone.sh <droplet_ip> <domain>
#
set -e

DROPLET_IP="$1"
DOMAIN="$2"

if [ -z "$DROPLET_IP" ] || [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <droplet_ip> <domain>"
  echo "Example: $0 137.184.204.157 jys8tas.decoupled.io"
  exit 1
fi

echo "🔐 Setting up SSL for $DOMAIN on droplet $DROPLET_IP"

# Wait for DNS to propagate.
echo "⏳ Waiting for DNS to propagate..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  RESOLVED_IP=$(dig +short "$DOMAIN" @8.8.8.8 | head -1)
  if [ "$RESOLVED_IP" = "$DROPLET_IP" ]; then
    echo "✅ DNS resolved correctly: $DOMAIN -> $DROPLET_IP"
    break
  fi
  
  ATTEMPT=$((ATTEMPT + 1))
  echo "   Attempt $ATTEMPT/$MAX_ATTEMPTS: DNS not ready yet (got: $RESOLVED_IP, expected: $DROPLET_IP)"
  
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "⚠️  DNS did not propagate in time. SSL setup may fail."
    echo "   You can run this script again later once DNS has propagated."
    exit 1
  fi
  
  sleep 10
done

echo ""
echo "📜 Obtaining Let's Encrypt certificate..."

# Run certbot on the droplet.
ssh -o StrictHostKeyChecking=no root@"$DROPLET_IP" bash <<'ENDSSH'
set -e

DOMAIN="'"$DOMAIN"'"
EMAIL="admin@decoupled.io"

echo "Running certbot for $DOMAIN..."

# Get the certificate.
certbot certonly --nginx \
  -d "$DOMAIN" \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  2>&1 | grep -E "(Successfully|error)" || true

# Check if certificate was created.
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  echo "❌ Certificate creation failed"
  exit 1
fi

echo "✅ Certificate obtained successfully"

# Update nginx configuration to use SSL.
echo "Configuring nginx for HTTPS..."

cat > /etc/nginx/sites-available/drupal <<'ENDNGINX'
server {
  listen 80;
  server_name DOMAIN_PLACEHOLDER;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl http2;
  server_name DOMAIN_PLACEHOLDER;
  root /opt/drupalcloud/web;

  ssl_certificate /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers HIGH:!aNULL:!MD5;

  location = /favicon.ico {
    log_not_found off;
    access_log off;
  }

  location = /robots.txt {
    allow all;
    log_not_found off;
    access_log off;
  }

  location ~ \..*/.*\.php$ {
    return 403;
  }

  location ~ ^/sites/.*/private/ {
    return 403;
  }

  location ~ ^/sites/[^/]+/files/.*\.php$ {
    deny all;
  }

  location ~* ^/.well-known/ {
    allow all;
  }

  location ~ (^|/)\. {
    return 403;
  }

  location / {
    try_files $uri /index.php?$query_string;
  }

  location @rewrite {
    rewrite ^/(.*)$ /index.php?q=$1;
  }

  location ~ /vendor/.*\.php$ {
    deny all;
    return 404;
  }

  location ~ '\.php$|^/update.php' {
    fastcgi_split_path_info ^(.+?\.php)(|/.*)$;
    include fastcgi_params;
    fastcgi_param HTTP_PROXY "";
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param PATH_INFO $fastcgi_path_info;
    fastcgi_param QUERY_STRING $query_string;
    fastcgi_intercept_errors on;
    fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
  }

  location ~ ^/sites/.*/files/styles/ {
    try_files $uri @rewrite;
  }

  location ~ ^(/[a-z\-]+)?/system/files/ {
    try_files $uri /index.php?$query_string;
  }

  location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
    try_files $uri @rewrite;
    expires max;
    log_not_found off;
  }
}
ENDNGINX

# Replace placeholder with actual domain.
sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" /etc/nginx/sites-available/drupal

# Test nginx configuration.
nginx -t

# Reload nginx.
systemctl reload nginx

echo "✅ Nginx configured and reloaded"

ENDSSH

echo ""
echo "✅ SSL setup complete!"
echo "🔒 Site is now accessible at: https://$DOMAIN"
echo ""

