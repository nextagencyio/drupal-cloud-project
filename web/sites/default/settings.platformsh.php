<?php

/**
 * @file
 * Platform.sh/Upsun-specific settings.
 *
 * This file is included from settings.php when running on Platform.sh/Upsun.
 */

// Platform.sh/Upsun configuration.
if (getenv('PLATFORM_RELATIONSHIPS')) {
  $relationships = json_decode(base64_decode(getenv('PLATFORM_RELATIONSHIPS')), TRUE);

  if (isset($relationships['database'])) {
    $database = $relationships['database'][0];
    $databases['default']['default'] = [
      'driver' => 'mysql',
      'database' => $database['path'],
      'username' => $database['username'],
      'password' => $database['password'],
      'host' => $database['host'],
      'port' => $database['port'],
      'namespace' => 'Drupal\\mysql\\Driver\\Database\\mysql',
      'autoload' => 'core/modules/mysql/src/Driver/Database/mysql/',
    ];
  }

  // Configure Redis if available.
  if (isset($relationships['redis'])) {
    $redis = $relationships['redis'][0];
    $settings['redis.connection']['interface'] = 'PhpRedis';
    $settings['redis.connection']['host'] = $redis['host'];
    $settings['redis.connection']['port'] = $redis['port'];
    $settings['cache']['default'] = 'cache.backend.redis';
    $settings['cache']['bins']['bootstrap'] = 'cache.backend.chainedfast';
    $settings['cache']['bins']['discovery'] = 'cache.backend.chainedfast';
    $settings['cache']['bins']['config'] = 'cache.backend.chainedfast';
  }

  // Set file paths for Upsun.
  $settings['file_private_path'] = '../private';
  $settings['config_sync_directory'] = '../config/sync';

  // Reverse proxy configuration for Upsun.
  $settings['reverse_proxy'] = TRUE;
  $settings['reverse_proxy_addresses'] = [@$_SERVER['REMOTE_ADDR']];

  // Trusted host patterns for Upsun.
  $settings['trusted_host_patterns'] = [
    '^.+\.platformsh\.site$',
    '^.+\.platform\.sh$',
  ];

  // Hash salt from environment.
  $settings['hash_salt'] = getenv('PLATFORM_PROJECT_ENTROPY') ?: 'temporary-hash-salt';
}
