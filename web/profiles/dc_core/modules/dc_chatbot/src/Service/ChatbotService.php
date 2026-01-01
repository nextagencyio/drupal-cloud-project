<?php

namespace Drupal\dc_chatbot\Service;

use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Logger\LoggerChannelFactoryInterface;

/**
 * Service for handling chatbot logic.
 */
class ChatbotService {

  /**
   * The config factory.
   *
   * @var \Drupal\Core\Config\ConfigFactoryInterface
   */
  protected $configFactory;

  /**
   * The logger factory.
   *
   * @var \Drupal\Core\Logger\LoggerChannelFactoryInterface
   */
  protected $loggerFactory;

  /**
   * Constructs a new ChatbotService object.
   *
   * @param \Drupal\Core\Config\ConfigFactoryInterface $config_factory
   *   The config factory.
   * @param \Drupal\Core\Logger\LoggerChannelFactoryInterface $logger_factory
   *   The logger factory.
   */
  public function __construct(ConfigFactoryInterface $config_factory, LoggerChannelFactoryInterface $logger_factory) {
    $this->configFactory = $config_factory;
    $this->loggerFactory = $logger_factory;
  }

  /**
   * Processes a chat message and returns a response.
   *
   * @param string $message
   *   The user message.
   * @param array $context
   *   Additional context data.
   *
   * @return string
   *   The chatbot response.
   */
  public function processMessage(string $message, array $context = []) {
    $config = $this->configFactory->get('dc_chatbot.settings');

    if (!$config->get('enabled', FALSE)) {
      return 'Chatbot is currently disabled.';
    }

    // Log the interaction
    $this->loggerFactory->get('dc_chatbot')->info('Chat message processed: @message', [
      '@message' => substr($message, 0, 100),
    ]);

    // Try to call the Next.js API first
    try {
      $nextjsResponse = $this->callNextjsAPI($message, $context);
      if ($nextjsResponse) {
        return $nextjsResponse;
      }
    }
    catch (\Exception $e) {
      $this->loggerFactory->get('dc_chatbot')->warning('Next.js API failed, falling back to local: @error', [
        '@error' => $e->getMessage(),
      ]);
    }

    // Fallback to local simple response logic
    return $this->generateResponse($message, $context);
  }

  /**
   * Generates a response based on the message.
   *
   * @param string $message
   *   The user message.
   * @param array $context
   *   Additional context data.
   *
   * @return string
   *   The generated response.
   */
  protected function generateResponse(string $message, array $context = []) {
    $message_lower = strtolower(trim($message));

    // Simple pattern matching - replace with AI service integration
    $responses = [
      'hello' => 'Hello! How can I help you today?',
      'hi' => 'Hi there! What can I do for you?',
      'help' => 'I\'m here to help! You can ask me questions about this site or general information.',
      'bye' => 'Goodbye! Feel free to come back anytime if you need help.',
      'goodbye' => 'Goodbye! Have a great day!',
      'thank' => 'You\'re welcome! Is there anything else I can help you with?',
    ];

    foreach ($responses as $trigger => $response) {
      if (strpos($message_lower, $trigger) !== FALSE) {
        return $response;
      }
    }

    // Default response
    return 'I understand you said: "' . $message . '". I\'m still learning! Can you try rephrasing your question?';
  }

  /**
   * Calls the Next.js API to get a chatbot response.
   *
   * @param string $message
   *   The user message.
   * @param array $context
   *   Additional context data.
   *
   * @return string|null
   *   The response from Next.js API or NULL if failed.
   */
  protected function callNextjsAPI(string $message, array $context = []) {
    $config = $this->configFactory->get('dc_chatbot.settings');

    // Get Next.js API URL from configuration
    $nextjsApiUrl = $config->get('api_url');
    if (empty($nextjsApiUrl)) {
      // No fallback detection - require explicit configuration
      \Drupal::logger('dc_chatbot')->error('Next.js API URL is not configured. Please configure it in the chatbot settings.');
      throw new \Exception('Next.js API URL is not configured. Please configure the chatbot settings.');
    }

    // Extract space ID from context or derive from hostname
    $spaceId = $context['spaceId'] ?? '';
    if (empty($spaceId)) {
      $request = \Drupal::request();
      $host = $request->getHttpHost();
      $parts = explode('.', $host);
      if (count($parts) >= 3) {
        $spaceId = $parts[0]; // Use subdomain as space ID
      }
      else {
        $spaceId = $host;
      }
    }

    $apiUrl = rtrim($nextjsApiUrl, '/');

    $payload = [
      'message' => $message,
      'spaceId' => $spaceId,
      'context' => $context,
    ];

    // Forward mode parameter if present in context
    if (isset($context['mode'])) {
      $payload['mode'] = $context['mode'];
    }

    // Get the API key for authentication
    $apiKey = $config->get('api_key');
    if (empty($apiKey)) {
      throw new \Exception('Chatbot API key is not configured. Please configure the chatbot settings.');
    }

    // Get the current request to determine origin
    $request = \Drupal::request();
    $scheme = $request->getScheme();
    $host = $request->getHttpHost();
    $origin = $scheme . '://' . $host;

    $options = [
      'http' => [
        'method' => 'POST',
        'header' => [
          'Content-Type: application/json',
          'User-Agent: Decoupled-Chatbot/1.0',
          'X-API-Key: ' . $apiKey,
          'Origin: ' . $origin,
        ],
        'content' => json_encode($payload),
        'timeout' => 30,
      ],
    ];

    $streamContext = stream_context_create($options);
    $response = @file_get_contents($apiUrl, FALSE, $streamContext);

    if ($response === FALSE) {
      throw new \Exception('Failed to connect to Next.js API');
    }

    $data = json_decode($response, TRUE);
    if (json_last_error() !== JSON_ERROR_NONE) {
      throw new \Exception('Invalid JSON response from Next.js API');
    }

    if (isset($data['error'])) {
      throw new \Exception($data['error']);
    }

    return $data['response'] ?? NULL;
  }

}
