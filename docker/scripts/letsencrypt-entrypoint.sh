#!/bin/bash
# Custom entrypoint for letsencrypt container
# Runs certificate symlink fix in background and starts normal acme-companion

# Start the certificate symlink fixer in background
/docker-scripts/fix-cert-symlinks.sh &

# Watch for new certificates and re-run the fix script
(
  while true; do
    sleep 3600  # Check every hour
    /docker-scripts/fix-cert-symlinks.sh
  done
) &

# Start the original acme-companion entrypoint
exec /bin/bash /app/entrypoint.sh "$@"
