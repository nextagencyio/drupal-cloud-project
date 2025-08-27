<?php

namespace Drupal\dcloud_import\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\dcloud_import\Service\DrupalContentImporter;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * REST API controller for dcloud_import.
 */
class ImportApiController extends ControllerBase {

  /**
   * The Drupal content importer service.
   *
   * @var \Drupal\dcloud_import\Service\DrupalContentImporter
   */
  protected $importer;

  /**
   * Constructs a new ImportApiController.
   *
   * @param \Drupal\dcloud_import\Service\DrupalContentImporter $importer
   *   The Drupal content importer service.
   */
  public function __construct(DrupalContentImporter $importer) {
    $this->importer = $importer;
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('dcloud_import.importer')
    );
  }

  /**
   * Import content from JSON via REST API.
   *
   * @param \Symfony\Component\HttpFoundation\Request $request
   *   The request object.
   *
   * @return \Symfony\Component\HttpFoundation\JsonResponse
   *   The JSON response.
   */
  public function import(Request $request) {
    try {
      // Check authentication
      if (!$this->authenticateRequest($request)) {
        return new JsonResponse([
          'success' => false,
          'error' => 'Authentication required. Please provide a valid DrupalCloud personal access token.',
          'format' => 'X-DCloud-Token: dc_tok_...',
          'help' => 'Get your token from the DrupalCloud dashboard at /organization/tokens',
        ], 401);
      }

      // Check method
      if ($request->getMethod() !== 'POST') {
        return new JsonResponse([
          'success' => false,
          'error' => 'Only POST method is allowed',
        ], 405);
      }

      // Get and validate JSON data
      $content = $request->getContent();
      if (empty($content)) {
        return new JsonResponse([
          'success' => false,
          'error' => 'Request body cannot be empty',
        ], 400);
      }

      $data = json_decode($content, TRUE);
      if (json_last_error() !== JSON_ERROR_NONE) {
        return new JsonResponse([
          'success' => false,
          'error' => 'Invalid JSON: ' . json_last_error_msg(),
        ], 400);
      }

      // Validate required structure - allow either "model" or "content" or both
      if (!isset($data['model']) && !isset($data['content'])) {
        return new JsonResponse([
          'success' => false,
          'error' => 'Invalid JSON structure. Expected "model" and/or "content" arrays.',
        ], 400);
      }

      // Check for preview mode
      $preview = $request->query->get('preview') === 'true';

      // Perform the import
      $result = $this->importer->import($data, $preview);

      return new JsonResponse($result);

    } catch (\Exception $e) {
      \Drupal::logger('dcloud_import')->error('Import error: @message', [
        '@message' => $e->getMessage(),
      ]);

      return new JsonResponse([
        'success' => false,
        'error' => 'Import failed: ' . $e->getMessage(),
      ], 500);
    }
  }

  /**
   * Get service status.
   *
   * @return \Symfony\Component\HttpFoundation\JsonResponse
   *   The JSON response.
   */
  public function status() {
    return new JsonResponse([
      'success' => true,
      'service' => 'DCloud Import API',
      'version' => '1.0.0',
      'endpoints' => [
        'POST /api/dcloud-import' => 'Import content models and data',
        'GET /api/dcloud-import/status' => 'Get service status',
      ],
      'authentication' => [
        'required' => 'X-DCloud-Token: dc_tok_... (DrupalCloud personal access token)',
        'note' => 'Get your token from the DrupalCloud dashboard at /organization/tokens',
        'oauth' => 'This endpoint does not use OAuth - use DCloud personal access tokens only',
      ],
      'documentation' => 'See module README for JSON format and examples',
    ]);
  }

    /**
   * Authenticate the request using personal access tokens.
   *
   * @param \Symfony\Component\HttpFoundation\Request $request
   *   The request object.
   *
   * @return bool
   *   TRUE if authenticated, FALSE otherwise.
   */
  private function authenticateRequest(Request $request) {
    // DCloud Personal Access Token authentication (no OAuth dependency)
    $token = $request->headers->get('X-DCloud-Token');
    
    if ($token && str_starts_with($token, 'dc_tok_')) {
      if ($this->validatePlatformToken($token)) {
        return TRUE;
      }
    }

    // Development mode bypass for .ddev.site domains
    $skipAuth = getenv('DCLOUD_SKIP_AUTH') === 'true' ||
                \Drupal::state()->get('dcloud_import.skip_auth', FALSE) ||
                ($request->headers->get('X-DCloud-Dev-Mode') === 'true' && str_contains($_SERVER['HTTP_HOST'] ?? '', '.ddev.site'));
    if ($skipAuth) {
      \Drupal::logger('dcloud_import')->warning('Authentication skipped - development mode');
      return TRUE;
    }

    return FALSE;
  }





  /**
   * Validate platform personal access token.
   *
   * @param string $token
   *   The platform token to validate.
   *
   * @return bool
   *   TRUE if valid, FALSE otherwise.
   */
  private function validatePlatformToken($token) {
        // Get platform URL from environment or settings
    $platformUrl = getenv('DCLOUD_PLATFORM_URL') ?:
                   \Drupal::state()->get('dcloud_import.platform_url', 'https://dashboard.dcloud.dev');

    // For local development, support localhost
    if (str_contains($_SERVER['HTTP_HOST'] ?? '', '.ddev.site')) {
      $platformUrl = 'http://host.docker.internal:3333';
    }
    
    \Drupal::logger('dcloud_import')->info('Attempting token validation against: @url', ['@url' => $platformUrl . '/api/auth/validate']);

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $platformUrl . '/api/auth/validate');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
      'Authorization: Bearer ' . $token,
      'Accept: application/json'
    ]);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false); // For local development

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($error) {
      \Drupal::logger('dcloud_import')->warning('Platform token validation failed: @error', [
        '@error' => $error
      ]);
      return FALSE;
    }

    if ($httpCode === 200) {
      $data = json_decode($response, TRUE);
      if (isset($data['valid']) && $data['valid'] === TRUE) {
        \Drupal::logger('dcloud_import')->info('Platform token validated successfully');
        return TRUE;
      }
    }

    \Drupal::logger('dcloud_import')->warning('Platform token validation failed: HTTP @code', [
      '@code' => $httpCode
    ]);
    return FALSE;
  }

}
