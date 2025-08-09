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