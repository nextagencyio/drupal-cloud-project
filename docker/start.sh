#!/bin/bash
set -e

# Ensure Xdebug is always disabled in runtime
export XDEBUG_MODE=off

# Start PHP-FPM in background
php-fpm -D

# Start nginx in foreground
nginx -g 'daemon off;'