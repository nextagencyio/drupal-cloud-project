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
  public function import(Request $request): JsonResponse {
    // Only allow POST requests.
    if ($request->getMethod() !== 'POST') {
      return new JsonResponse([
        'error' => 'Method not allowed. Use POST.',
      ], Response::HTTP_METHOD_NOT_ALLOWED);
    }

    // Get JSON from request body.
    $json_data = $request->getContent();
    if (empty($json_data)) {
      return new JsonResponse([
        'error' => 'Empty request body. JSON data required.',
      ], Response::HTTP_BAD_REQUEST);
    }

    // Decode JSON.
    $data = json_decode($json_data, TRUE);
    if (json_last_error() !== JSON_ERROR_NONE) {
      return new JsonResponse([
        'error' => 'Invalid JSON format: ' . json_last_error_msg(),
      ], Response::HTTP_BAD_REQUEST);
    }

    // Validate the structure.
    if (!$this->validateImportData($data)) {
      return new JsonResponse([
        'error' => 'Invalid JSON structure. Expected "model" and optionally "content" arrays.',
      ], Response::HTTP_BAD_REQUEST);
    }

    // Check for preview mode.
    $preview_mode = $request->query->get('preview', FALSE);
    $preview_mode = filter_var($preview_mode, FILTER_VALIDATE_BOOLEAN);

    try {
      // Perform the import.
      $result = $this->importer->import($data, $preview_mode);

      // Return success response.
      $response_data = [
        'success' => TRUE,
        'preview' => $preview_mode,
        'operations' => count($result['summary'] ?? []),
        'messages' => [
          'summary' => $result['summary'] ?? [],
          'warnings' => $result['warnings'] ?? [],
        ],
      ];

      return new JsonResponse($response_data, Response::HTTP_OK);

    } catch (\Exception $e) {
      // Return error response.
      return new JsonResponse([
        'success' => FALSE,
        'error' => $e->getMessage(),
      ], Response::HTTP_INTERNAL_SERVER_ERROR);
    }
  }

  /**
   * Get import status/health check.
   *
   * @return \Symfony\Component\HttpFoundation\JsonResponse
   *   The JSON response.
   */
  public function status(): JsonResponse {
    try {
      return new JsonResponse([
        'service' => 'dcloud_import',
        'version' => '1.0.0',
        'status' => 'ready',
        'endpoints' => [
          'POST /api/dcloud-import' => 'Import content from JSON',
          'GET /api/dcloud-import/status' => 'Service status',
        ],
        'authentication' => 'OAuth 2.0 Bearer token required',
        'documentation' => [
          'preview' => 'Add ?preview=true to test import without making changes',
          'format' => 'Send JSON with "model" array for content types and optional "content" array for content',
        ],
      ], Response::HTTP_OK);
    } catch (\Exception $e) {
      return new JsonResponse([
        'error' => 'Controller error: ' . $e->getMessage(),
      ], Response::HTTP_INTERNAL_SERVER_ERROR);
    }
  }

  /**
   * Validates the import data structure.
   *
   * @param array $data
   *   The decoded JSON data.
   *
   * @return bool
   *   TRUE if valid, FALSE otherwise.
   */
  private function validateImportData(array $data): bool {
    if (!isset($data['model']) || !is_array($data['model'])) {
      return FALSE;
    }

    foreach ($data['model'] as $item) {
      if (!is_array($item) || !isset($item['bundle']) || !isset($item['label'])) {
        return FALSE;
      }
    }

    return TRUE;
  }

}