<?php

namespace Drupal\dcloud_usage\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Database\Connection;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\File\FileSystemInterface;
use Drupal\node\Entity\NodeType;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;

/**
 * Controller for usage statistics endpoints.
 */
class UsageController extends ControllerBase {

  /**
   * The database connection.
   *
   * @var \Drupal\Core\Database\Connection
   */
  protected $database;

  /**
   * The entity type manager.
   *
   * @var \Drupal\Core\Entity\EntityTypeManagerInterface
   */
  protected $entityTypeManager;

  /**
   * The file system service.
   *
   * @var \Drupal\Core\File\FileSystemInterface
   */
  protected $fileSystem;

  /**
   * Constructs a UsageController object.
   *
   * @param \Drupal\Core\Database\Connection $database
   *   The database connection.
   * @param \Drupal\Core\Entity\EntityTypeManagerInterface $entity_type_manager
   *   The entity type manager.
   * @param \Drupal\Core\File\FileSystemInterface $file_system
   *   The file system service.
   */
  public function __construct(Connection $database, EntityTypeManagerInterface $entity_type_manager, FileSystemInterface $file_system) {
    $this->database = $database;
    $this->entityTypeManager = $entity_type_manager;
    $this->fileSystem = $file_system;
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('database'),
      $container->get('entity_type.manager'),
      $container->get('file_system')
    );
  }

  /**
   * Returns basic usage statistics.
   *
   * @param \Symfony\Component\HttpFoundation\Request $request
   *   The request object.
   *
   * @return \Symfony\Component\HttpFoundation\JsonResponse
   *   JSON response with usage statistics.
   */
  public function getUsageStats(Request $request) {
    try {
      $stats = [
        'content_types' => $this->getContentTypeCount(),
        'entities' => $this->getEntityStats(),
        'api_requests' => $this->getApiRequestStats(),
        'storage' => $this->getStorageStats(),
        'bandwidth' => $this->getBandwidthStats(),
        'users' => $this->getUserCount(),
        'timestamp' => time(),
      ];

      return new JsonResponse($stats);
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error fetching usage stats: @message', ['@message' => $e->getMessage()]);
      return new JsonResponse(['error' => 'Failed to fetch usage statistics'], 500);
    }
  }

  /**
   * Returns detailed usage statistics.
   *
   * @param \Symfony\Component\HttpFoundation\Request $request
   *   The request object.
   *
   * @return \Symfony\Component\HttpFoundation\JsonResponse
   *   JSON response with detailed usage statistics.
   */
  public function getDetailedUsage(Request $request) {
    try {
      $stats = [
        'content_types' => $this->getContentTypeCount(),
        'content_type_details' => $this->getContentTypeDetails(),
        'entities' => $this->getEntityStats(),
        'entity_details' => $this->getEntityDetails(),
        'api_requests' => $this->getApiRequestStats(),
        'storage' => $this->getStorageStats(),
        'storage_details' => $this->getStorageDetails(),
        'bandwidth' => $this->getBandwidthStats(),
        'users' => $this->getUserCount(),
        'user_details' => $this->getUserDetails(),
        'system_info' => $this->getSystemInfo(),
        'timestamp' => time(),
      ];

      return new JsonResponse($stats);
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error fetching detailed usage stats: @message', ['@message' => $e->getMessage()]);
      return new JsonResponse(['error' => 'Failed to fetch detailed usage statistics'], 500);
    }
  }

  /**
   * Gets the count of content types.
   *
   * @return int
   *   The number of content types.
   */
  protected function getContentTypeCount() {
    try {
      $node_types = NodeType::loadMultiple();
      return count($node_types);
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error counting content types: @message', ['@message' => $e->getMessage()]);
      return 0;
    }
  }

  /**
   * Gets content type details.
   *
   * @return array
   *   Array of content type information.
   */
  protected function getContentTypeDetails() {
    try {
      $node_types = NodeType::loadMultiple();
      $details = [];
      
      foreach ($node_types as $type) {
        $details[] = [
          'id' => $type->id(),
          'label' => $type->label(),
          'description' => $type->getDescription(),
        ];
      }
      
      return $details;
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting content type details: @message', ['@message' => $e->getMessage()]);
      return [];
    }
  }

  /**
   * Gets entity statistics.
   *
   * @return array
   *   Array with entity counts.
   */
  protected function getEntityStats() {
    try {
      $node_storage = $this->entityTypeManager->getStorage('node');
      
      // Get total count
      $total_query = $node_storage->getQuery()
        ->accessCheck(FALSE)
        ->count();
      $total = $total_query->execute();

      // Get count by type
      $by_type = [];
      $node_types = NodeType::loadMultiple();
      
      foreach ($node_types as $type_id => $type) {
        $type_query = $node_storage->getQuery()
          ->condition('type', $type_id)
          ->accessCheck(FALSE)
          ->count();
        $count = $type_query->execute();
        
        if ($count > 0) {
          $by_type[$type_id] = $count;
        }
      }

      return [
        'total' => $total,
        'by_type' => $by_type,
      ];
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting entity stats: @message', ['@message' => $e->getMessage()]);
      return ['total' => 0, 'by_type' => []];
    }
  }

  /**
   * Gets detailed entity information.
   *
   * @return array
   *   Array with detailed entity information.
   */
  protected function getEntityDetails() {
    try {
      $node_storage = $this->entityTypeManager->getStorage('node');
      $node_types = NodeType::loadMultiple();
      $details = [];

      foreach ($node_types as $type_id => $type) {
        $query = $node_storage->getQuery()
          ->condition('type', $type_id)
          ->accessCheck(FALSE)
          ->count();
        $count = $query->execute();

        if ($count > 0) {
          // Get published vs unpublished counts
          $published_query = $node_storage->getQuery()
            ->condition('type', $type_id)
            ->condition('status', 1)
            ->accessCheck(FALSE)
            ->count();
          $published = $published_query->execute();

          $details[$type_id] = [
            'label' => $type->label(),
            'total' => $count,
            'published' => $published,
            'unpublished' => $count - $published,
          ];
        }
      }

      return $details;
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting entity details: @message', ['@message' => $e->getMessage()]);
      return [];
    }
  }

  /**
   * Gets API request statistics.
   *
   * @return array
   *   Array with API request stats.
   */
  protected function getApiRequestStats() {
    // For now, return placeholder data
    // In a full implementation, this would track actual API requests
    return [
      'total_monthly' => 0,
      'by_type' => [
        'graphql' => 0,
        'jsonapi' => 0,
        'rest' => 0,
      ],
      'daily_average' => 0,
    ];
  }

  /**
   * Gets storage statistics.
   *
   * @return array
   *   Array with storage information.
   */
  protected function getStorageStats() {
    try {
      $database_size = $this->getDatabaseSize();
      $files_size = $this->getFilesSize();

      return [
        'database_mb' => round($database_size / 1024 / 1024, 2),
        'files_mb' => round($files_size / 1024 / 1024, 2),
        'total_mb' => round(($database_size + $files_size) / 1024 / 1024, 2),
      ];
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting storage stats: @message', ['@message' => $e->getMessage()]);
      return ['database_mb' => 0, 'files_mb' => 0, 'total_mb' => 0];
    }
  }

  /**
   * Gets detailed storage information.
   *
   * @return array
   *   Array with detailed storage information.
   */
  protected function getStorageDetails() {
    try {
      $file_storage = $this->entityTypeManager->getStorage('file');
      
      // Get file count
      $file_query = $file_storage->getQuery()
        ->accessCheck(FALSE)
        ->count();
      $file_count = $file_query->execute();

      // Get file size by type
      $files = $file_storage->loadMultiple();
      $by_type = [];
      $total_size = 0;

      foreach ($files as $file) {
        $mime_type = $file->getMimeType();
        $size = $file->getSize();
        $total_size += $size;

        if (!isset($by_type[$mime_type])) {
          $by_type[$mime_type] = ['count' => 0, 'size' => 0];
        }
        $by_type[$mime_type]['count']++;
        $by_type[$mime_type]['size'] += $size;
      }

      return [
        'file_count' => $file_count,
        'total_file_size' => $total_size,
        'by_mime_type' => $by_type,
      ];
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting storage details: @message', ['@message' => $e->getMessage()]);
      return [];
    }
  }

  /**
   * Gets bandwidth statistics.
   *
   * @return array
   *   Array with bandwidth stats.
   */
  protected function getBandwidthStats() {
    // For now, return placeholder data
    // In a full implementation, this would track actual bandwidth usage
    return [
      'monthly_gb' => 0,
      'daily_average_mb' => 0,
    ];
  }

  /**
   * Gets user count.
   *
   * @return int
   *   The number of users (excluding anonymous user).
   */
  protected function getUserCount() {
    try {
      $user_storage = $this->entityTypeManager->getStorage('user');
      $query = $user_storage->getQuery()
        ->condition('uid', 0, '>')  // Exclude anonymous user (uid=0)
        ->accessCheck(FALSE)
        ->count();
      
      return $query->execute();
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error counting users: @message', ['@message' => $e->getMessage()]);
      return 0;
    }
  }

  /**
   * Gets detailed user information.
   *
   * @return array
   *   Array with user details.
   */
  protected function getUserDetails() {
    try {
      $user_storage = $this->entityTypeManager->getStorage('user');
      
      // Get total users (excluding anonymous)
      $total_query = $user_storage->getQuery()
        ->condition('uid', 0, '>')
        ->accessCheck(FALSE)
        ->count();
      $total = $total_query->execute();

      // Get active users (logged in within last 30 days)
      $thirty_days_ago = time() - (30 * 24 * 60 * 60);
      $active_query = $user_storage->getQuery()
        ->condition('uid', 0, '>')
        ->condition('access', $thirty_days_ago, '>')
        ->accessCheck(FALSE)
        ->count();
      $active = $active_query->execute();

      // Get blocked users
      $blocked_query = $user_storage->getQuery()
        ->condition('uid', 0, '>')
        ->condition('status', 0)
        ->accessCheck(FALSE)
        ->count();
      $blocked = $blocked_query->execute();

      return [
        'total' => $total,
        'active_30_days' => $active,
        'blocked' => $blocked,
        'active' => $total - $blocked,
      ];
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting user details: @message', ['@message' => $e->getMessage()]);
      return [];
    }
  }

  /**
   * Gets system information.
   *
   * @return array
   *   Array with system information.
   */
  protected function getSystemInfo() {
    try {
      return [
        'drupal_version' => \Drupal::VERSION,
        'php_version' => PHP_VERSION,
        'database_type' => $this->database->databaseType(),
        'site_name' => \Drupal::config('system.site')->get('name'),
        'install_time' => \Drupal::state()->get('install_time'),
      ];
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting system info: @message', ['@message' => $e->getMessage()]);
      return [];
    }
  }

  /**
   * Gets database size in bytes.
   *
   * @return int
   *   Database size in bytes.
   */
  protected function getDatabaseSize() {
    try {
      $database_type = $this->database->databaseType();
      
      if ($database_type === 'sqlite') {
        // For SQLite, get the database file size
        $database_info = $this->database->getConnectionOptions();
        if (isset($database_info['database']) && file_exists($database_info['database'])) {
          return filesize($database_info['database']);
        }
      }
      elseif ($database_type === 'mysql') {
        // For MySQL, query information_schema
        $database_name = $this->database->getConnectionOptions()['database'];
        $query = $this->database->query("
          SELECT SUM(data_length + index_length) as size 
          FROM information_schema.tables 
          WHERE table_schema = :database
        ", [':database' => $database_name]);
        
        $result = $query->fetchField();
        return $result ? (int) $result : 0;
      }
      
      return 0;
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting database size: @message', ['@message' => $e->getMessage()]);
      return 0;
    }
  }

  /**
   * Gets total files size in bytes.
   *
   * @return int
   *   Files size in bytes.
   */
  protected function getFilesSize() {
    try {
      $file_storage = $this->entityTypeManager->getStorage('file');
      $files = $file_storage->loadMultiple();
      
      $total_size = 0;
      foreach ($files as $file) {
        $total_size += $file->getSize();
      }
      
      return $total_size;
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_usage')->error('Error getting files size: @message', ['@message' => $e->getMessage()]);
      return 0;
    }
  }

}