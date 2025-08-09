<?php

namespace Drupal\dcloud_chatbot\Plugin\Block;

use Drupal\Core\Access\AccessResult;
use Drupal\Core\Block\BlockBase;
use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Plugin\ContainerFactoryPluginInterface;
use Drupal\Core\Session\AccountInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Provides a 'Chatbot' Block.
 *
 * @Block(
 *   id = "dcloud_chatbot_block",
 *   admin_label = @Translation("DCloud Chatbot"),
 *   category = @Translation("DCloud"),
 * )
 */
class ChatbotBlock extends BlockBase implements ContainerFactoryPluginInterface {

  /**
   * The config factory.
   *
   * @var \Drupal\Core\Config\ConfigFactoryInterface
   */
  protected $configFactory;

  /**
   * Constructs a new ChatbotBlock object.
   *
   * @param array $configuration
   *   A configuration array containing information about the plugin instance.
   * @param string $plugin_id
   *   The plugin_id for the plugin instance.
   * @param mixed $plugin_definition
   *   The plugin implementation definition.
   * @param \Drupal\Core\Config\ConfigFactoryInterface $config_factory
   *   The config factory.
   */
  public function __construct(array $configuration, $plugin_id, $plugin_definition, ConfigFactoryInterface $config_factory) {
    parent::__construct($configuration, $plugin_id, $plugin_definition);
    $this->configFactory = $config_factory;
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container, array $configuration, $plugin_id, $plugin_definition) {
    return new static(
      $configuration,
      $plugin_id,
      $plugin_definition,
      $container->get('config.factory')
    );
  }

  /**
   * {@inheritdoc}
   */
  public function defaultConfiguration() {
    return [
      'button_text' => $this->t('Chat with us'),
      'button_position' => 'bottom-right',
      'button_color' => '#007cba',
      'show_on_mobile' => TRUE,
      'trigger_delay' => 0,
    ] + parent::defaultConfiguration();
  }

  /**
   * {@inheritdoc}
   */
  public function blockForm($form, FormStateInterface $form_state) {
    $form = parent::blockForm($form, $form_state);

    $config = $this->getConfiguration();

    $form['button_text'] = [
      '#type' => 'textfield',
      '#title' => $this->t('Button Text'),
      '#description' => $this->t('The text displayed on the chatbot trigger button.'),
      '#default_value' => $config['button_text'],
      '#required' => TRUE,
      '#maxlength' => 50,
    ];

    $form['button_position'] = [
      '#type' => 'select',
      '#title' => $this->t('Button Position'),
      '#description' => $this->t('Where to position the chatbot trigger button on the page.'),
      '#default_value' => $config['button_position'],
      '#options' => [
        'bottom-right' => $this->t('Bottom Right'),
        'bottom-left' => $this->t('Bottom Left'),
        'top-right' => $this->t('Top Right'),
        'top-left' => $this->t('Top Left'),
      ],
    ];

    $form['button_color'] = [
      '#type' => 'color',
      '#title' => $this->t('Button Color'),
      '#description' => $this->t('The background color of the chatbot trigger button.'),
      '#default_value' => $config['button_color'],
    ];

    $form['show_on_mobile'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('Show on Mobile'),
      '#description' => $this->t('Display the chatbot on mobile devices.'),
      '#default_value' => $config['show_on_mobile'],
    ];

    $form['trigger_delay'] = [
      '#type' => 'number',
      '#title' => $this->t('Auto-trigger Delay (seconds)'),
      '#description' => $this->t('Automatically open the chatbot after this many seconds. Set to 0 to disable.'),
      '#default_value' => $config['trigger_delay'],
      '#min' => 0,
      '#max' => 300,
      '#step' => 1,
    ];

    return $form;
  }

  /**
   * {@inheritdoc}
   */
  public function blockSubmit($form, FormStateInterface $form_state) {
    parent::blockSubmit($form, $form_state);
    $this->configuration['button_text'] = $form_state->getValue('button_text');
    $this->configuration['button_position'] = $form_state->getValue('button_position');
    $this->configuration['button_color'] = $form_state->getValue('button_color');
    $this->configuration['show_on_mobile'] = $form_state->getValue('show_on_mobile');
    $this->configuration['trigger_delay'] = $form_state->getValue('trigger_delay');
  }

  /**
   * {@inheritdoc}
   */
  public function build() {
    $config = $this->configFactory->get('dcloud_chatbot.settings');
    $block_config = $this->getConfiguration();

    // Don't render if chatbot is disabled
    if (!$config->get('enabled', FALSE)) {
      return [];
    }

    // Don't render if API key is not configured
    if (empty($config->get('api_key'))) {
      return [];
    }

    return [
      '#theme' => 'dcloud_chatbot_block',
      '#button_text' => $block_config['button_text'],
      '#button_position' => $block_config['button_position'],
      '#button_color' => $block_config['button_color'],
      '#show_on_mobile' => $block_config['show_on_mobile'],
      '#trigger_delay' => $block_config['trigger_delay'],
      '#welcome_message' => $config->get('welcome_message', 'Hello! How can I help you today?'),
      '#attached' => [
        'library' => [
          'dcloud_chatbot/chatbot',
        ],
        'drupalSettings' => [
          'dcloudChatbot' => [
            'enabled' => TRUE,
            'buttonPosition' => $block_config['button_position'],
            'buttonColor' => $block_config['button_color'],
            'showOnMobile' => $block_config['show_on_mobile'],
            'triggerDelay' => $block_config['trigger_delay'] * 1000, // Convert to milliseconds
            'welcomeMessage' => $config->get('welcome_message', 'Hello! How can I help you today?'),
            'spaceId' => $this->getSpaceId(),
            'nextjsApiUrl' => $this->getNextjsApiUrl(),
          ],
        ],
      ],
      '#cache' => [
        'tags' => ['config:dcloud_chatbot.settings'],
        'contexts' => ['user.permissions'],
      ],
    ];
  }

  /**
   * {@inheritdoc}
   */
  protected function blockAccess(AccountInterface $account) {
    return AccessResult::allowedIfHasPermission($account, 'use dcloud chatbot');
  }

  /**
   * Get the space ID for this site.
   * 
   * This method attempts to identify the current space/site ID
   * that can be used to map to the Next.js dashboard.
   */
  protected function getSpaceId() {
    // Try to get from environment variable or settings
    $space_id = getenv('DCLOUD_SPACE_ID');
    if ($space_id) {
      return $space_id;
    }

    // Try to extract from the site's base URL or hostname
    $request = \Drupal::request();
    $host = $request->getHttpHost();
    
    // If using subdomain pattern (e.g., spacename.domain.com)
    $parts = explode('.', $host);
    if (count($parts) >= 3) {
      return $parts[0]; // Return subdomain as space ID
    }
    
    // Fallback: use the full hostname
    return $host;
  }

  /**
   * Get the Next.js API URL.
   */
  protected function getNextjsApiUrl() {
    // Check for environment variable first
    $api_url = getenv('NEXTJS_API_URL');
    if ($api_url) {
      return rtrim($api_url, '/');
    }

    // Check for site-specific configuration
    $config = $this->configFactory->get('dcloud_chatbot.settings');
    $configured_url = $config->get('nextjs_api_url');
    if ($configured_url) {
      return rtrim($configured_url, '/');
    }

    // Development/local fallback
    $request = \Drupal::request();
    $host = $request->getHttpHost();
    
    if (strpos($host, 'localhost') !== FALSE || strpos($host, '127.0.0.1') !== FALSE) {
      return 'http://localhost:3000';
    }

    // Production fallback - assume dashboard subdomain
    $parts = explode('.', $host);
    if (count($parts) >= 2) {
      return 'https://dashboard.' . implode('.', array_slice($parts, 1));
    }

    return 'https://dashboard.drupalcloud.com';
  }

}