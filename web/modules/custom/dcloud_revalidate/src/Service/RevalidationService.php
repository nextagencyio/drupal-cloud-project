<?php

namespace Drupal\dcloud_revalidate\Service;

use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Logger\LoggerChannelFactoryInterface;
use Drupal\node\NodeInterface;
use GuzzleHttp\ClientInterface;
use GuzzleHttp\Exception\RequestException;

/**
 * Service for handling Next.js revalidation requests.
 */
class RevalidationService {

  /**
   * The HTTP client.
   *
   * @var \GuzzleHttp\ClientInterface
   */
  protected $httpClient;

  /**
   * The config factory.
   *
   * @var \Drupal\Core\Config\ConfigFactoryInterface
   */
  protected $configFactory;

  /**
   * The logger channel.
   *
   * @var \Drupal\Core\Logger\LoggerChannelInterface
   */
  protected $logger;

  /**
   * Constructs a RevalidationService object.
   *
   * @param \GuzzleHttp\ClientInterface $http_client
   *   The HTTP client.
   * @param \Drupal\Core\Config\ConfigFactoryInterface $config_factory
   *   The config factory.
   * @param \Drupal\Core\Logger\LoggerChannelFactoryInterface $logger_factory
   *   The logger channel factory.
   */
  public function __construct(ClientInterface $http_client, ConfigFactoryInterface $config_factory, LoggerChannelFactoryInterface $logger_factory) {
    $this->httpClient = $http_client;
    $this->configFactory = $config_factory;
    $this->logger = $logger_factory->get('dcloud_revalidate');
  }

  /**
   * Triggers revalidation for a node.
   *
   * @param \Drupal\node\NodeInterface $node
   *   The node to revalidate.
   *
   * @return bool
   *   TRUE if revalidation was triggered successfully, FALSE otherwise.
   */
  public function revalidateNode(NodeInterface $node) {
    $config = $this->configFactory->get('dcloud_revalidate.settings');

    if (!$config->get('enabled')) {
      return FALSE;
    }

    $frontend_url = $config->get('frontend_url');
    $secret = $config->get('revalidate_secret');

    if (empty($frontend_url) || empty($secret)) {
      $this->logger->error('Revalidation failed: Missing frontend URL or secret.');
      return FALSE;
    }

    $slug = $this->getNodeSlug($node);
    if (empty($slug)) {
      $this->logger->warning('Revalidation skipped: No slug found for node @nid.', ['@nid' => $node->id()]);
      return FALSE;
    }

    return $this->sendRevalidationRequest($frontend_url, $secret, $slug);
  }

  /**
   * Gets the slug for a node.
   *
   * @param \Drupal\node\NodeInterface $node
   *   The node.
   *
   * @return string|null
   *   The node slug or NULL if not found.
   */
  protected function getNodeSlug(NodeInterface $node) {
    // Check for path alias first
    $alias = \Drupal::service('path_alias.manager')->getAliasByPath('/node/' . $node->id());
    if ($alias !== '/node/' . $node->id()) {
      return ltrim($alias, '/');
    }

    // Fallback to node ID
    return 'node/' . $node->id();
  }

  /**
   * Sends a revalidation request to the Next.js frontend.
   *
   * @param string $frontend_url
   *   The frontend URL.
   * @param string $secret
   *   The revalidation secret.
   * @param string $slug
   *   The slug to revalidate.
   *
   * @return bool
   *   TRUE if the request was successful, FALSE otherwise.
   */
  protected function sendRevalidationRequest($frontend_url, $secret, $slug) {
    $url = rtrim($frontend_url, '/') . '/api/revalidate';

    try {
      $response = $this->httpClient->post($url, [
        'form_params' => [
          'secret' => $secret,
          'slug' => $slug,
        ],
        'timeout' => 10,
      ]);

      if ($response->getStatusCode() === 200) {
        $this->logger->info('Revalidation successful for slug: @slug', ['@slug' => $slug]);
        return TRUE;
      }
      else {
        $this->logger->error('Revalidation failed for slug: @slug. Status: @status', [
          '@slug' => $slug,
          '@status' => $response->getStatusCode(),
        ]);
        return FALSE;
      }
    }
    catch (RequestException $e) {
      $this->logger->error('Revalidation request failed for slug: @slug. Error: @error', [
        '@slug' => $slug,
        '@error' => $e->getMessage(),
      ]);
      return FALSE;
    }
  }

}