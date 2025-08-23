<?php

namespace Drupal\dcloud_config\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Url;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Drupal\Component\Utility\Crypt;
use Drupal\Component\Utility\Random;

/**
 * Controller for Drupal Cloud configuration page.
 */
class DcloudConfigController extends ControllerBase {

  /**
   * The entity type manager.
   *
   * @var \Drupal\Core\Entity\EntityTypeManagerInterface
   */
  protected $entityTypeManager;

  /**
   * The config factory.
   *
   * @var \Drupal\Core\Config\ConfigFactoryInterface
   */
  protected $configFactory;

  /**
   * Constructs a DcloudConfigController object.
   *
   * @param \Drupal\Core\Entity\EntityTypeManagerInterface $entity_type_manager
   *   The entity type manager.
   * @param \Drupal\Core\Config\ConfigFactoryInterface $config_factory
   *   The config factory.
   */
  public function __construct(EntityTypeManagerInterface $entity_type_manager, ConfigFactoryInterface $config_factory) {
    $this->entityTypeManager = $entity_type_manager;
    $this->configFactory = $config_factory;
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('entity_type.manager'),
      $container->get('config.factory')
    );
  }

  /**
   * Homepage that shows configuration information.
   *
   * @return array|\Symfony\Component\HttpFoundation\RedirectResponse
   *   A render array or redirect response.
   */
  public function homePage() {
    // Check if user has permission to administer site configuration.
    if (!$this->currentUser()->hasPermission('administer site configuration')) {
      return new RedirectResponse('/user');
    }

    // Show the configuration page for authorized users.
    return $this->configPage();
  }

  /**
   * Helper function to create a code block with copy and download buttons.
   *
   * @param string $code
   *   The code content.
   * @param string $language
   *   The language type (optional).
   * @param string $title
   *   The title for the code block (optional).
   * @param bool $show_download
   *   Whether to show the download button (optional).
   *
   * @return string
   *   HTML markup for code block with copy and download buttons.
   */
  private function createCodeBlock($code, $language = '', $title = '', $show_download = FALSE) {
    $id = 'code-' . uniqid();
    $title_html = $title ? '<div class="dcloud-config-code-title">' . $title . '</div>' : '';
    $has_title_class = $title ? ' has-title' : '';

    $download_button = '';
    if ($show_download) {
      $download_button = '<button class="dcloud-config-download-button" data-target="' . $id . '" data-filename=".env.local" title="Download as .env file">
          💾 Download
        </button>';
    }

    return '<div class="dcloud-config-code-block' . $has_title_class . '">
      ' . $title_html . '
      <div class="dcloud-config-code-content">
        <pre id="' . $id . '">' . htmlspecialchars($code) . '</pre>
        <div class="dcloud-config-buttons">
          <button class="dcloud-config-copy-button" data-target="' . $id . '" title="Copy to clipboard">
            📋 Copy
          </button>
          ' . $download_button . '
        </div>
      </div>
    </div>';
  }

  /**
   * Displays the Next.js configuration page.
   *
   * @return array
   *   A render array.
   */
  public function configPage() {
    $build = [];

    // Attach the custom library for styling and JavaScript.
    $build['#attached']['library'][] = 'dcloud_config/dcloud_config';

    // Get or create Next.js consumer information.
    $client_id = '';
    $client_secret = '';

    try {
      $consumer_storage = $this->entityTypeManager->getStorage('consumer');
      // Clear cache to ensure we get fresh data
      $consumer_storage->resetCache();
      $consumers = $consumer_storage->loadByProperties(['label' => 'Next.js Frontend']);

      if (empty($consumers)) {
        // Create the OAuth consumer automatically.
        $consumer = $this->createOAuthConsumer($consumer_storage);
        if (!$consumer) {
          // If consumer creation fails, generate temporary values.
          $client_id = 'TEMP_' . bin2hex(random_bytes(16));
          $client_secret = bin2hex(random_bytes(16));

          $build['warning'] = [
            '#type' => 'markup',
            '#markup' => '<div class="messages messages--warning">
              <h3>⚠️ Temporary Configuration</h3>
              <p>OAuth consumer could not be created automatically. Using temporary values below.</p>
              <p>For production use, please create the OAuth consumer manually or run: <code>ddev drush php:script scripts/consumers-next.php</code></p>
            </div>',
          ];
        }
        else {
          $client_id = $consumer->getClientId();
          $client_secret = $consumer->get('secret')->value;
        }
      }
      else {
        $consumer = reset($consumers);
        $client_id = $consumer->getClientId();

        // Get the secret from the secret field
        $stored_secret = $consumer->get('secret')->value;

        // If the consumer exists but has no secret, or if it's hashed,
        // show placeholder instead of auto-generating.
        if (empty($stored_secret) || preg_match('/^\$2[ayb]\$/', $stored_secret)) {
          $client_secret = '[OAuth consumer needs secret - contact administrator]';
        }
        else {
          // If we have a plain text secret already, use it.
          $client_secret = $stored_secret;
        }
      }
    }
    catch (\Exception $e) {
      // If all else fails, provide temporary values.
      $client_id = 'TEMP_' . bin2hex(random_bytes(16));
      $client_secret = bin2hex(random_bytes(16));

      $build['error'] = [
        '#type' => 'markup',
        '#markup' => '<div class="messages messages--warning">
          <h3>⚠️ Temporary Configuration</h3>
          <p>Could not access OAuth consumer storage. Using temporary values below.</p>
          <p>Error: ' . htmlspecialchars($e->getMessage()) . '</p>
          <p>For production use, please ensure all required modules are installed and configured properly.</p>
        </div>',
      ];
    }

    // Get Next.js settings.
    $next_config = $this->configFactory->get('next.settings');
    $next_base_url = $next_config->get('base_url') ?: 'http://host.docker.internal:3333';

    // Get revalidate secret from dcloud_revalidate.settings
    $revalidate_config = $this->configFactory->get('dcloud_revalidate.settings');
    $revalidate_secret = $revalidate_config->get('revalidate_secret');

    // Generate revalidation secret if it doesn't exist
    if (empty($revalidate_secret) || $revalidate_secret === 'not-set') {
      $random = new Random();
      $revalidate_secret = bin2hex(random_bytes(16));

      // Save the new revalidation secret to dcloud_revalidate.settings
      $revalidate_config_editable = $this->configFactory->getEditable('dcloud_revalidate.settings');
      $revalidate_config_editable->set('revalidate_secret', $revalidate_secret);
      $revalidate_config_editable->save();
    }

    // Get current site URL.
    global $base_url;
    $site_url = $base_url ?: \Drupal::request()->getSchemeAndHttpHost();

    // Prepare code blocks.
    $env_content = "# Required - Drupal backend URL
NEXT_PUBLIC_DRUPAL_BASE_URL=" . $site_url . "
NEXT_IMAGE_DOMAIN=" . parse_url($site_url, PHP_URL_HOST) . "

# Authentication - OAuth credentials
DRUPAL_CLIENT_ID=" . $client_id . "
DRUPAL_CLIENT_SECRET=" . $client_secret . "

# Required for On-demand Revalidation
DRUPAL_REVALIDATE_SECRET=" . $revalidate_secret . "

# Allow self-signed certificates for development (DDEV)
NODE_TLS_REJECT_UNAUTHORIZED=0";

    $npm_run_dev = "npm run dev";

    $build['instructions'] = [
      '#type' => 'markup',
      '#markup' => '<div class="dcloud-config-main-layout">
        <div class="dcloud-config-content-area">
          <div class="dcloud-config-header">
            <div class="dcloud-config-logo">
              <div class="dcloud-config-logo-icon">DC</div>
              <div class="dcloud-config-logo-text">Drupal Cloud</div>
            </div>
            <h1>Your headless CMS is ready!</h1>
            <p>Follow the steps below to connect your Next.js frontend and start building.</p>
          </div>

          <div class="dcloud-config-main-content">
            <div class="dcloud-config-tip">
              <div class="dcloud-config-tip-icon">💡</div>
              <div>
                <p><strong>Pro Tip:</strong> All code blocks below have copy buttons (📋) in the top-right corner. Click to copy instantly!</p>
              </div>
            </div>

            <div class="dcloud-config-section">
              <h2>🔧 Environment Configuration</h2>
              <p>Create or update your <code>.env.local</code> file in your Next.js project root:</p>

              ' . $this->createCodeBlock($env_content, 'env', '.env.local', TRUE) . '

              <div class="dcloud-config-generate-secret">
                <form method="post" action="/dcloud-config/generate-secret" style="display: inline;">
                  <input type="hidden" name="form_token" value="' . \Drupal::csrfToken()->get('dcloud_config_generate_secret') . '">
                  <button type="submit" class="dcloud-config-generate-button">
                    🔑&nbsp;&nbsp;Generate New Client Secret
                  </button>
                </form>
                <p class="dcloud-config-generate-help">Generate a new OAuth client secret for enhanced security.</p>
              </div>
            </div>

            <div class="dcloud-config-section">
              <h2>🚀 Get Started</h2>
              <p>Choose your preferred setup method:</p>

              <!-- Featured Vercel Deploy Option -->
              <div class="dcloud-config-featured-option">
                <div class="dcloud-config-featured-card">
                  <div class="dcloud-config-featured-header">
                    <div class="dcloud-config-featured-badge">⚡ RECOMMENDED</div>
                    <h3>☁️ Deploy to Vercel</h3>
                    <p>Get your site live in production with one click - no setup required!</p>
                  </div>
                  <div class="dcloud-config-vercel-deploy">
                    <a href="https://vercel.com/new/clone?repository-url=https://github.com/nextagencyio/drupal-cloud-starter&project-name=my-app"
                       target="_blank"
                       class="dcloud-config-vercel-button-large">
                      <svg width="24" height="24" viewBox="0 0 76 65" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <path d="m37.5274 0 36.9815 64H.5459Z" fill="currentColor"/>
                      </svg>
                      Deploy with Vercel
                      <span class="dcloud-config-arrow">→</span>
                    </a>

                  </div>
                </div>
              </div>

              <!-- Alternative Options -->
              <div class="dcloud-config-alternative-header">
                <h3>Or choose an alternative setup:</h3>
              </div>

              <div class="dcloud-config-setup-options">
                <div class="dcloud-config-option-card dcloud-config-single-option">
                  <div class="dcloud-config-option-header">
                    <h3>🆕 New Project</h3>
                    <p>Create a new project with our starter template</p>
                  </div>
                  ' . $this->createCodeBlock("# Create new project with starter template
npx create-drupal-cloud-starter

# Copy or download the .env.local variables above
# and add them to your project root

# Start the development server
npm run dev", 'bash', 'Quick Start Commands') . '
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="dcloud-config-sidebar">
          <div class="dcloud-config-sidebar-card">
            <div class="dcloud-config-sidebar-content">
            <h3>
              <span class="dcloud-config-sidebar-icon">📋</span>
              Setup Checklist
            </h3>
            <div class="dcloud-config-checklist">
              <div class="dcloud-config-checklist-item">
                <div class="dcloud-config-step-number">1</div>
                <div class="dcloud-config-step-content">
                  <div class="dcloud-config-step-title">Copy Environment Variables</div>
                  <div class="dcloud-config-step-description">Add the .env.local configuration to your Next.js project</div>
                </div>
              </div>
              <div class="dcloud-config-checklist-item">
                <div class="dcloud-config-step-number">2</div>
                <div class="dcloud-config-step-content">
                  <div class="dcloud-config-step-title">Install Dependencies</div>
                  <div class="dcloud-config-step-description">Run npm install in your project directory</div>
                </div>
              </div>
              <div class="dcloud-config-checklist-item">
                <div class="dcloud-config-step-number">3</div>
                <div class="dcloud-config-step-content">
                  <div class="dcloud-config-step-title">Start Development Server</div>
                  <div class="dcloud-config-step-description">Run npm run dev to start your application</div>
                </div>
              </div>
              <div class="dcloud-config-checklist-item">
                <div class="dcloud-config-step-number">4</div>
                <div class="dcloud-config-step-content">
                  <div class="dcloud-config-step-title">Test Connection</div>
                  <div class="dcloud-config-step-description">Verify your frontend connects to this Drupal backend</div>
                </div>
              </div>
            </div>

            <div class="dcloud-config-help-links">
              <h4>📚 Resources</h4>
              <ul>
                <li><a href="https://github.com/nextagencyio/drupal-cloud-starter" target="_blank">Starter Project →</a></li>
                <li><a href="https://nextjs.org/docs" target="_blank">Next.js Docs →</a></li>
                <li><a href="/admin/config" target="_blank">Drupal Config →</a></li>
              </ul>
            </div>
            </div>
          </div>
        </div>
      </div>',
    ];

    // Allow HTML attributes to preserve styling.
    $build['instructions']['#allowed_tags'] = [
      'div',
      'h1',
      'h2',
      'h3',
      'h4',
      'p',
      'pre',
      'code',
      'button',
      'form',
      'input',
      'ul',
      'li',
      'a',
      'strong',
      'br',
      'script',
    ];

    return $build;
  }

  /**
   * Creates an OAuth consumer for Next.js frontend.
   *
   * @param \Drupal\Core\Entity\EntityStorageInterface $consumer_storage
   *   The consumer storage service.
   *
   * @return \Drupal\consumer\Entity\Consumer|null
   *   The created consumer entity or null if creation failed.
   */
  private function createOAuthConsumer($consumer_storage) {
    try {
      $random = new Random();

      $client_id = Crypt::randomBytesBase64();
      $client_secret = $random->word(8);

      // Create previewer consumer data.
      $consumer_data = [
        'client_id' => $client_id,
        'client_secret' => $client_secret,
        'label' => 'Next.js Frontend',
        'user_id' => 2,
        'third_party' => TRUE,
        'is_default' => FALSE,
      ];

      // Check if consumer__roles table exists before adding roles.
      $database = \Drupal::database();
      if ($database->schema()->tableExists('consumer__roles')) {
        $consumer_data['roles'] = ['previewer'];
      }

      $consumer = $consumer_storage->create($consumer_data);
      $consumer->save();

      return $consumer;
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_config')->error('Failed to create OAuth consumer: @message', ['@message' => $e->getMessage()]);
      return NULL;
    }
  }

  /**
   * Generates a new revalidation secret and OAuth client secret.
   *
   * @param \Symfony\Component\HttpFoundation\Request $request
   *   The current request.
   *
   * @return \Symfony\Component\HttpFoundation\RedirectResponse
   *   A redirect response back to the configuration page.
   */
  public function generateSecret(Request $request) {
    // Check if user has permission to administer site configuration.
    if (!$this->currentUser()->hasPermission('administer site configuration')) {
      return new RedirectResponse('/user');
    }

    // Verify CSRF token
    $token = $request->request->get('form_token');
    if (!\Drupal::csrfToken()->validate($token, 'dcloud_config_generate_secret')) {
      \Drupal::messenger()->addError('Invalid form token. Please try again.');
      return new RedirectResponse(Url::fromRoute('dcloud_config.homepage')->toString());
    }


    // Also regenerate OAuth client secret if needed
    try {
      $consumer_storage = $this->entityTypeManager->getStorage('consumer');
      $consumers = $consumer_storage->loadByProperties(['label' => 'Next.js Frontend']);

      if (!empty($consumers)) {
        $consumer = reset($consumers);

        // Always generate a new plain text secret when the button is clicked
        $random = new Random();
        $client_secret = $random->word(8);

        // Set the secret field directly
        $consumer->set('secret', $client_secret);
        $consumer->save();

        // Clear entity cache to ensure fresh data on page reload
        $consumer_storage->resetCache([$consumer->id()]);
        \Drupal::entityTypeManager()->clearCachedDefinitions();

        \Drupal::logger('dcloud_config')->info('Generated new OAuth client secret: @secret', ['@secret' => $client_secret]);
      }
    }
    catch (\Exception $e) {
      \Drupal::logger('dcloud_config')->error('Failed to update OAuth consumer secret: @message', ['@message' => $e->getMessage()]);
    }

    // Add success message
    \Drupal::messenger()->addStatus('New client secret generated successfully!');

    // Redirect back to the configuration page
    return new RedirectResponse(Url::fromRoute('dcloud_config.homepage')->toString());
  }

  /**
   * AJAX endpoint to generate new OAuth client secret.
   *
   * @param \Symfony\Component\HttpFoundation\Request $request
   *   The current request.
   *
   * @return \Symfony\Component\HttpFoundation\JsonResponse
   *   A JSON response with the new client secret.
   */
  public function generateSecretAjax(Request $request) {
    // Check if user has permission to administer site configuration.
    if (!$this->currentUser()->hasPermission('administer site configuration')) {
      return new JsonResponse(['error' => 'Access denied'], 403);
    }

    // Verify CSRF token
    $token = $request->request->get('form_token');
    if (!\Drupal::csrfToken()->validate($token, 'dcloud_config_generate_secret')) {
      return new JsonResponse(['error' => 'Invalid form token'], 403);
    }

    $response_data = [
      'success' => false,
      'client_secret' => '',
      'client_id' => '',
      'revalidate_secret' => '',
      'message' => ''
    ];

    try {
      // Get existing revalidation secret to preserve it
      $revalidate_config = $this->configFactory->get('dcloud_revalidate.settings');
      $existing_revalidate_secret = $revalidate_config->get('revalidate_secret');

      // If no existing revalidate secret, generate one
      if (empty($existing_revalidate_secret) || $existing_revalidate_secret === 'not-set') {
        $random = new Random();
        $existing_revalidate_secret = bin2hex(random_bytes(16));

        // Save the new revalidate secret to config
        $revalidate_config_editable = $this->configFactory->getEditable('dcloud_revalidate.settings');
        $revalidate_config_editable->set('revalidate_secret', $existing_revalidate_secret);
        $revalidate_config_editable->save();
      }

      $response_data['revalidate_secret'] = $existing_revalidate_secret;

      // Regenerate OAuth client secret
      $consumer_storage = $this->entityTypeManager->getStorage('consumer');
      $consumer_storage->resetCache();
      $consumers = $consumer_storage->loadByProperties(['label' => 'Next.js Frontend']);

      if (!empty($consumers)) {
        $consumer = reset($consumers);
        $response_data['client_id'] = $consumer->getClientId();

        // Generate new client secret
        $random = new Random();
        $client_secret = $random->word(8);

        $consumer->set('secret', $client_secret);
        $consumer->save();

        // Clear cache
        $consumer_storage->resetCache([$consumer->id()]);

        $response_data['client_secret'] = $client_secret;
        $response_data['success'] = true;
        $response_data['message'] = 'New client secret generated successfully!';
      } else {
        $response_data['error'] = 'OAuth consumer not found';
      }

    } catch (\Exception $e) {
      \Drupal::logger('dcloud_config')->error('AJAX secret generation failed: @message', ['@message' => $e->getMessage()]);
      $response_data['error'] = 'Failed to generate client secret: ' . $e->getMessage();
    }

    return new JsonResponse($response_data);
  }

}
