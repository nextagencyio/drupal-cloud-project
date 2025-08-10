<?php

namespace Drupal\dcloud_chatbot\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\dcloud_chatbot\Service\ChatbotService;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Controller for chatbot API endpoints.
 */
class ChatbotController extends ControllerBase {

  /**
   * The config factory.
   *
   * @var \Drupal\Core\Config\ConfigFactoryInterface
   */
  protected $configFactory;

  /**
   * The chatbot service.
   *
   * @var \Drupal\dcloud_chatbot\Service\ChatbotService
   */
  protected $chatbotService;

  /**
   * Constructs a new ChatbotController object.
   *
   * @param \Drupal\Core\Config\ConfigFactoryInterface $config_factory
   *   The config factory.
   * @param \Drupal\dcloud_chatbot\Service\ChatbotService $chatbot_service
   *   The chatbot service.
   */
  public function __construct(ConfigFactoryInterface $config_factory, ChatbotService $chatbot_service) {
    $this->configFactory = $config_factory;
    $this->chatbotService = $chatbot_service;
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('config.factory'),
      $container->get('dcloud_chatbot.chatbot_service')
    );
  }

  /**
   * Handles chat requests.
   *
   * @param \Symfony\Component\HttpFoundation\Request $request
   *   The request object.
   *
   * @return \Symfony\Component\HttpFoundation\JsonResponse
   *   The JSON response.
   */
  public function chat(Request $request) {
    try {
      $data = json_decode($request->getContent(), TRUE);

      if (empty($data['message'])) {
        return new JsonResponse([
          'error' => 'Message is required',
        ], Response::HTTP_BAD_REQUEST);
      }

      // Check if this is a model content request
      if (!empty($data['mode']) && $data['mode'] === 'model-content') {
        return $this->handleModelContentRequest($data);
      }

      $response = $this->chatbotService->processMessage($data['message'], $data);

      return new JsonResponse([
        'response' => $response,
        'timestamp' => time(),
      ]);
    }
    catch (\Exception $e) {
      $this->getLogger('dcloud_chatbot')->error('Chat error: @message', [
        '@message' => $e->getMessage(),
      ]);

      return new JsonResponse([
        'error' => 'Internal server error',
      ], Response::HTTP_INTERNAL_SERVER_ERROR);
    }
  }

  /**
   * Handle model content requests by forwarding to Next.js API.
   */
  private function handleModelContentRequest(array $data) {
    try {
      // Generate the configuration
      $json_config = $this->generateContentModelConfig($data['message']);
      
      // Import the configuration using dcloud_import
      $import_result = $this->importConfiguration($json_config);
      
      // Return the result
      $response = $this->formatImportResult($import_result);
      
      return new JsonResponse([
        'response' => $response,
        'timestamp' => time(),
      ]);
    }
    catch (\Exception $e) {
      $this->getLogger('dcloud_chatbot')->error('Model content error: @message', [
        '@message' => $e->getMessage(),
      ]);

      return new JsonResponse([
        'error' => 'Error generating content model: ' . $e->getMessage(),
      ], Response::HTTP_INTERNAL_SERVER_ERROR);
    }
  }

  /**
   * Forward request to Next.js API.
   */
  private function forwardToNextjsApi(string $nextjs_api_url, array $data) {
    try {
      // For now, let's use a simple mock response to test the flow
      $mock_response = "I'll create a blog post content type with title, content, author, and tags.\n\n```json\n{\n  \"model\": [\n    {\n      \"bundle\": \"blog_post\",\n      \"label\": \"Blog Post\",\n      \"description\": \"Content type for blog posts with title, content, author, and tags\",\n      \"body\": true,\n      \"fields\": [\n        {\n          \"id\": \"author\",\n          \"label\": \"Author\",\n          \"type\": \"string!\"\n        },\n        {\n          \"id\": \"tags\",\n          \"label\": \"Tags\",\n          \"type\": \"term(tags)[]\"\n        }\n      ]\n    }\n  ]\n}\n```\n\nConfiguration ready for dcloud_import.";
      
      return $mock_response;
      
      // TODO: Uncomment when Next.js API is properly configured
      /*
      $url = rtrim($nextjs_api_url, '/') . '/api/chatbot';
      
      $context = stream_context_create([
        'http' => [
          'method' => 'POST',
          'header' => 'Content-Type: application/json',
          'content' => json_encode($data),
          'timeout' => 30,
        ],
      ]);

      $response = file_get_contents($url, FALSE, $context);
      
      if ($response === FALSE) {
        throw new \Exception('Failed to connect to Next.js API');
      }

      $decoded = json_decode($response, TRUE);
      
      if (json_last_error() !== JSON_ERROR_NONE) {
        throw new \Exception('Invalid response from Next.js API');
      }

      return $decoded['response'] ?? 'No response from API';
      */
    }
    catch (\Exception $e) {
      $this->getLogger('dcloud_chatbot')->error('API forwarding error: @message', [
        '@message' => $e->getMessage(),
      ]);
      throw $e;
    }
  }

  /**
   * Generate content model configuration based on user description.
   */
  private function generateContentModelConfig(string $description) {
    // Simple logic to generate basic configuration with sample content
    // In a full implementation, this would call the AI service
    
    if (stripos($description, 'blog') !== FALSE) {
      return [
        'model' => [
          [
            'bundle' => 'blog_post',
            'label' => 'Blog Post',
            'description' => 'Content type for blog posts',
            'body' => TRUE,
            'fields' => [
              [
                'id' => 'author',
                'label' => 'Author',
                'type' => 'string!',
              ],
              [
                'id' => 'tags',
                'label' => 'Tags', 
                'type' => 'term(tags)[]',
              ],
            ],
          ],
        ],
        'content' => [
          [
            'id' => 'sample_blog_1',
            'type' => 'node.blog_post',
            'path' => '/blog/getting-started-drupal-cloud',
            'values' => [
              'title' => 'Getting Started with Drupal Cloud',
              'body' => '<p>Welcome to Drupal Cloud! This is your first blog post to help you get started with the platform...</p>',
              'author' => 'Admin User',
              'tags' => [
                'drupal',
                'getting-started'
              ],
            ],
          ],
          [
            'id' => 'sample_blog_2', 
            'type' => 'node.blog_post',
            'path' => '/blog/headless-cms-benefits',
            'values' => [
              'title' => 'Benefits of Headless CMS Architecture',
              'body' => '<p>Discover the advantages of using a headless CMS approach for modern web development...</p>',
              'author' => 'Content Manager',
              'tags' => [
                'headless',
                'cms'
              ],
            ],
          ],
        ],
      ];
    }
    
    // Default configuration with sample content
    return [
      'model' => [
        [
          'bundle' => 'custom_content',
          'label' => 'Custom Content',
          'description' => 'Generated content type',
          'body' => TRUE,
          'fields' => [],
        ],
      ],
      'content' => [
        [
          'id' => 'sample_content_1',
          'type' => 'node.custom_content',
          'path' => '/content/sample-content',
          'values' => [
            'title' => 'Sample Content',
            'body' => '<p>This is sample content created by the chatbot.</p>',
          ],
        ],
      ],
    ];
  }

  /**
   * Import configuration using dcloud_import service.
   */
  private function importConfiguration(array $config) {
    try {
      // Get the dcloud_import service
      $importer = \Drupal::service('dcloud_import.importer');
      
      // Perform the import
      $result = $importer->import($config, FALSE);
      
      return $result;
    }
    catch (\Exception $e) {
      throw new \Exception('Import failed: ' . $e->getMessage());
    }
  }

  /**
   * Format import result for user response.
   */
  private function formatImportResult(array $result) {
    $summary = $result['summary'] ?? [];
    $warnings = $result['warnings'] ?? [];
    $created_nodes = $result['created_nodes'] ?? [];
    
    if (empty($summary)) {
      return 'Configuration imported successfully!';
    }
    
    $response = "✅ **Content model created successfully!**\n\n";
    
    // Deduplicate summary items
    $unique_summary = array_unique($summary);
    
    // Extract node information from summary messages for later use
    $created_content = [];
    foreach ($unique_summary as $item) {
      // Look for "Created node: Title (ID: X, type: Y)" pattern
      if (preg_match('/Created node: (.+) \(ID: (\d+), type: (.+)\)/', $item, $matches)) {
        $title = $matches[1];
        $nid = $matches[2];
        $type = $matches[3];
        
        $created_content[] = [
          'title' => $title,
          'nid' => $nid,
          'type' => $type
        ];
      }
    }
    
    foreach ($unique_summary as $item) {
      $response .= "• {$item}\n";
    }
    
    if (!empty($warnings)) {
      $response .= "\n⚠️ **Warnings:**\n";
      // Deduplicate warnings too
      $unique_warnings = array_unique($warnings);
      foreach ($unique_warnings as $warning) {
        $response .= "• {$warning}\n";
      }
    }
    
    // Add links to created content at the end
    if (!empty($created_content)) {
      $response .= "\n📄 **Sample content created:**\n";
      foreach ($created_content as $node_info) {
        $title = $node_info['title'];
        $nid = $node_info['nid'];
        
        $edit_link = "/node/{$nid}/edit";
        $response .= "• [{$title}]({$edit_link})\n";
      }
    }
    
    return $response;
  }

  /**
   * Handles chatbot configuration requests.
   *
   * @param \Symfony\Component\HttpFoundation\Request $request
   *   The request object.
   *
   * @return \Symfony\Component\HttpFoundation\JsonResponse
   *   The JSON response.
   */
  public function chatbotConfig(Request $request) {
    $config = $this->configFactory->get('dcloud_chatbot.settings');

    if ($request->isMethod('POST')) {
      $data = json_decode($request->getContent(), TRUE);

      if (isset($data['api_key'])) {
        $config_editable = $this->configFactory->getEditable('dcloud_chatbot.settings');
        $config_editable->set('api_key', $data['api_key']);
        // Auto-enable the chatbot when API key is configured
        $config_editable->set('enabled', TRUE);
        
        // Set Next.js API URL if provided
        if (isset($data['nextjs_api_url'])) {
          $config_editable->set('nextjs_api_url', $data['nextjs_api_url']);
        }
        
        $config_editable->save();

        return new JsonResponse(['status' => 'API key updated and chatbot enabled']);
      }
    }

    return new JsonResponse([
      'enabled' => $config->get('enabled', FALSE),
      'api_key_configured' => !empty($config->get('api_key')),
    ]);
  }

}