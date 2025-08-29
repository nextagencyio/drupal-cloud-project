<?php

/**
 * @file
 * Create consumers and generate keys for Drupal Cloud Next.js integration.
 */

use Drupal\Component\Utility\Crypt;
use Drupal\Component\Utility\Random;
use Drupal\Core\DrupalKernel;

$messages = [];

// Initialize variables.
$previewerClientId = '';
$previewerClientSecret = '';

// Get the current site directory.
$request = \Drupal::request();
$site_path = DrupalKernel::findSitePath($request);

// Use absolute path for private directory.
$private_path = DRUPAL_ROOT . '/' . $site_path . '/private';

// Ensure private directory exists and is writable.
if (!is_dir($private_path)) {
  mkdir($private_path, 0755, TRUE);
}

// Configure OAuth settings with key paths (always set these).
try {
  $config = \Drupal::configFactory()->getEditable('simple_oauth.settings');
  $config->set('public_key', $site_path . '/private/public.key');
  $config->set('private_key', $site_path . '/private/private.key');
  $config->save();
  $messages[] = 'OAuth key paths configured: ' . $site_path . '/private/';
}
catch (Exception $e) {
  $messages[] = 'Error configuring OAuth key paths: ' . $e->getMessage();
}

// Generate keys if private path is writable and keys don't exist.
if (is_writable($private_path)) {
  $public_key_path = $private_path . '/public.key';
  $private_key_path = $private_path . '/private.key';
  
  if (!file_exists($public_key_path) || !file_exists($private_key_path)) {
    try {
      // Generate OAuth keys.
      \Drupal::service('simple_oauth.key.generator')->generateKeys($private_path);
      $messages[] = 'OAuth keys generated successfully in ' . $private_path;
    }
    catch (Exception $e) {
      $messages[] = 'Error generating OAuth keys: ' . $e->getMessage();
    }
  } else {
    $messages[] = 'OAuth keys already exist in ' . $private_path;
  }
}

  // Copy recipe content files to site files directory.
  try {
    $files_path = DRUPAL_ROOT . '/' . $site_path . '/files';
    $content_path = $files_path . '/content';
    
    // Ensure content directory exists.
    if (!is_dir($content_path)) {
      mkdir($content_path, 0755, TRUE);
    }
    
    // Try multiple possible recipe locations.
    $possible_recipe_files = [
      DRUPAL_ROOT . '/../recipes/dcloud-core/content/file/article.png',
      '/var/www/html/recipes/dcloud-core/content/file/article.png',
      '/home/drupalcloud/drupal-cloud-project/recipes/dcloud-core/content/file/article.png',
    ];
    
    $recipe_file = null;
    foreach ($possible_recipe_files as $file) {
      if (file_exists($file)) {
        $recipe_file = $file;
        break;
      }
    }
    
    if ($recipe_file) {
      $target_file = $content_path . '/article.png';
      if (copy($recipe_file, $target_file)) {
        $messages[] = 'Recipe content file copied: article.png';
      } else {
        $messages[] = 'Warning: Failed to copy article.png from recipe';
      }
    } else {
      $messages[] = 'Warning: Recipe file article.png not found in any expected location';
    }
  }
  catch (Exception $e) {
    $messages[] = 'Warning: Error copying recipe files: ' . $e->getMessage();
  }

  $random = new Random();
  $consumerStorage = \Drupal::entityTypeManager()->getStorage('consumer');

  // Delete existing consumers before creating new ones.
  $existing_consumers = $consumerStorage->loadByProperties([
    'label' => ['Next.js Frontend', 'Next.js Viewer']
  ]);
  foreach ($existing_consumers as $consumer) {
    $consumer->delete();
    $messages[] = 'Deleted existing consumer: ' . $consumer->label();
  }

  $previewerClientId = Crypt::randomBytesBase64();
  $previewerClientSecret = $random->word(8);

  // Create previewer consumer data.
  $previewerData = [
    'client_id' => $previewerClientId,
    'client_secret' => $previewerClientSecret,
    'label' => 'Next.js Frontend',
    'user_id' => 2,
    'third_party' => TRUE,
    'is_default' => FALSE,
  ];

  // Check if consumer__roles table exists before adding roles.
  $database = \Drupal::database();
  if ($database->schema()->tableExists('consumer__roles')) {
    $previewerData['roles'] = ['previewer'];
  }

  $consumerStorage->create($previewerData)->save();

  $viewerClientId = Crypt::randomBytesBase64();
  $viewerClientSecret = $random->word(8);

  // Create viewer consumer data.
  $viewerData = [
    'client_id' => $viewerClientId,
    'client_secret' => $viewerClientSecret,
    'label' => 'Next.js Viewer',
    'user_id' => 2,
    'third_party' => TRUE,
    'is_default' => FALSE,
  ];

  // Check if consumer__roles table exists before adding roles.
  if ($database->schema()->tableExists('consumer__roles')) {
    $viewerData['roles'] = ['viewer'];
  }

  $consumerStorage->create($viewerData)->save();

  $messages = [
    'Consumers created successfully. Please save the following credentials.',
    '--- Next.js Frontend (Previewer) ---',
    'DRUPAL_CLIENT_ID=' . $previewerClientId,
    'DRUPAL_CLIENT_SECRET=' . $previewerClientSecret,
    '--- Next.js Viewer ---',
    'DRUPAL_CLIENT_ID=' . $viewerClientId,
    'DRUPAL_CLIENT_SECRET=' . $viewerClientSecret,
  ];

// Check to see if ../drupal-cloud-starter/ is writable.
// If so go ahead and update configuration files.
if (is_writable('../drupal-cloud-starter/')) {
  // Get current domain.
  $host = \Drupal::request()->getSchemeAndHttpHost();

  // If the domain ends with .ddev.site, force https.
  if (strpos($host, '.ddev.site') !== FALSE) {
    $host = preg_replace('/^http:/', 'https:', $host);
  }

  // If file ../drupal-cloud-starter/.env.example exists copy to
  // ../drupal-cloud-starter/.env.local.
  $envFile = '../drupal-cloud-starter/.env.local';
  $envExampleFile = '../drupal-cloud-starter/.env.example';
  if (file_exists($envExampleFile) && !file_exists($envFile)) {
    copy($envExampleFile, $envFile);
    // Notify the user.
    $messages[] = 'Copied ' . $envExampleFile . ' to ' . $envFile;
  }

  // If file ../drupal-cloud-starter/.env.local exists then update the
  // credentials.
  if (file_exists($envFile) && !empty($previewerClientId) && !empty($previewerClientSecret)) {
    $envContents = file_get_contents($envFile);

    // Update NEXT_PUBLIC_DRUPAL_BASE_URL.
    $envContents = preg_replace(
      '/^NEXT_PUBLIC_DRUPAL_BASE_URL=.*$/m',
      'NEXT_PUBLIC_DRUPAL_BASE_URL=' . $host,
      $envContents
    );

    // Update NEXT_IMAGE_DOMAIN.
    $domain = parse_url($host, PHP_URL_HOST);
    $envContents = preg_replace(
      '/^NEXT_IMAGE_DOMAIN=.*$/m',
      'NEXT_IMAGE_DOMAIN=' . $domain,
      $envContents
    );

    // Update DRUPAL_CLIENT_ID.
    $envContents = preg_replace(
      '/^DRUPAL_CLIENT_ID=.*$/m',
      'DRUPAL_CLIENT_ID=' . $previewerClientId,
      $envContents
    );

    // Update DRUPAL_CLIENT_SECRET.
    $envContents = preg_replace(
      '/^DRUPAL_CLIENT_SECRET=.*$/m',
      'DRUPAL_CLIENT_SECRET=' . $previewerClientSecret,
      $envContents
    );

    // Generate and update DRUPAL_REVALIDATE_SECRET.
    $revalidateSecret = bin2hex(random_bytes(16));
    $envContents = preg_replace(
      '/^DRUPAL_REVALIDATE_SECRET=.*$/m',
      'DRUPAL_REVALIDATE_SECRET=' . $revalidateSecret,
      $envContents
    );

    // Save the revalidate secret to Drupal configuration.
    $revalidateConfig = \Drupal::configFactory()->getEditable('dcloud_revalidate.settings');
    $revalidateConfig->set('revalidate_secret', $revalidateSecret);
    $revalidateConfig->save();

    // Write the updated contents back to the file.
    file_put_contents($envFile, $envContents);

    // Notify the user.
    $messages[] = 'Credentials added to ' . $envFile;
    $messages[] = 'Revalidate secret: ' . $revalidateSecret;
  }
}

if (empty($messages)) {
  return;
}

if (PHP_SAPI === 'cli') {
  echo PHP_EOL;
  foreach ($messages as $message) {
    echo $message . PHP_EOL;
  }
  echo PHP_EOL;
}
else {
  foreach ($messages as $message) {
    \Drupal::messenger()->addWarning($message);
  }
}

// Small cleanup to delete erroneous folder.
if (file_exists('public:')) {
  rmdir('public:');
}
