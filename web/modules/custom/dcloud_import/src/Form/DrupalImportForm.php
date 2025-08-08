<?php

namespace Drupal\dcloud_import\Form;

use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\dcloud_import\Service\DrupalContentImporter;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Form for importing Drupal content configuration.
 */
class DrupalImportForm extends FormBase {

  /**
   * The Drupal content importer service.
   *
   * @var \Drupal\dcloud_import\Service\DrupalContentImporter
   */
  protected $importer;

  /**
   * Constructs a new DrupalImportForm.
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
   * {@inheritdoc}
   */
  public function getFormId() {
    return 'dcloud_import_form';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state) {
    $form['description'] = [
      '#markup' => '<p>' . $this->t('Import Drupal content types, paragraph types, and content from JSON configuration.') . '</p>',
    ];

    $form['json_data'] = [
      '#type' => 'textarea',
      '#title' => $this->t('JSON Configuration'),
      '#description' => $this->t('Paste your Drupal content configuration in JSON format.'),
      '#rows' => 20,
      '#required' => TRUE,
      '#default_value' => $this->getExampleJson(),
    ];

    $form['preview'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('Preview mode'),
      '#description' => $this->t('Check this to preview what would be created without actually creating it.'),
      '#default_value' => TRUE,
    ];

    $form['actions'] = [
      '#type' => 'actions',
    ];

    $form['actions']['submit'] = [
      '#type' => 'submit',
      '#value' => $this->t('Import'),
      '#button_type' => 'primary',
    ];

    return $form;
  }

  /**
   * {@inheritdoc}
   */
  public function validateForm(array &$form, FormStateInterface $form_state) {
    $json_data = $form_state->getValue('json_data');
    $data = json_decode($json_data, TRUE);

    if (json_last_error() !== JSON_ERROR_NONE) {
      $form_state->setErrorByName('json_data', $this->t('Invalid JSON format: @error', [
        '@error' => json_last_error_msg(),
      ]));
      return;
    }

    // Validate the concise model structure.
    if (!$this->validateConciseModel($data)) {
      $form_state->setErrorByName('json_data', $this->t('Invalid JSON structure. Expected "model" and optionally "content" arrays.'));
    }
  }

  /**
   * Validates the concise model structure.
   *
   * @param array $data
   *   The decoded JSON data.
   *
   * @return bool
   *   TRUE if valid, FALSE otherwise.
   */
  private function validateConciseModel(array $data): bool {
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

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state) {
    $json_data = $form_state->getValue('json_data');
    $preview_mode = $form_state->getValue('preview');
    $data = json_decode($json_data, TRUE);

    try {
      $result = $this->importer->import($data, $preview_mode);

      if ($preview_mode) {
        $this->messenger()->addStatus($this->t('Preview completed successfully. @count operations would be performed.', [
          '@count' => count($result),
        ]));
      }
      else {
        $this->messenger()->addStatus($this->t('Import completed successfully. @count operations performed.', [
          '@count' => count($result),
        ]));
      }

      // Display the results.
      foreach ($result as $operation) {
        $this->messenger()->addStatus($operation);
      }
    }
    catch (\Exception $e) {
      $this->messenger()->addError($this->t('Import failed: @error', [
        '@error' => $e->getMessage(),
      ]));
    }
  }

  /**
   * Returns example JSON for the form.
   *
   * @return string
   *   Example JSON configuration.
   */
  private function getExampleJson(): string {
    // Load example JSON from the module's resources file if available.
    $module_path = \Drupal::service('extension.list.module')->getPath('dcloud_import');
    $path = \Drupal::root() . '/' . $module_path . '/resources/sample.json';
    if (is_readable($path)) {
      $contents = file_get_contents($path);
      if ($contents !== FALSE && $contents !== '') {
        return $contents;
      }
    }

    // Fallback to embedded example JSON if the file is not available.
    return json_encode([
      'model' => [
        [
          'bundle' => 'blog_post',
          'label' => 'Blog Post',
          'body' => TRUE,
          'fields' => [
            ['id' => 'slug', 'label' => 'Slug', 'type' => 'string'],
            ['id' => 'hero_section', 'label' => 'Hero Section', 'type' => 'paragraph(hero_section)'],
            ['id' => 'publish_date', 'label' => 'Publish Date', 'type' => 'date'],
            ['id' => 'tags', 'label' => 'Tags', 'type' => 'term(tags)[]'],
            ['id' => 'featured', 'label' => 'Featured', 'type' => 'bool'],
          ],
        ],
        [
          'entity' => 'paragraph',
          'bundle' => 'hero_section',
          'label' => 'Hero Section',
          'fields' => [
            ['id' => 'title', 'label' => 'Title', 'type' => 'string!'],
            ['id' => 'subtitle', 'label' => 'Subtitle', 'type' => 'string'],
            ['id' => 'background_image', 'label' => 'Background Image', 'type' => 'image'],
          ],
        ],
      ],
      'content' => [
        [
          'id' => 'hero1',
          'type' => 'paragraph.hero_section',
          'values' => [
            'title' => 'Welcome to Our Site',
            'subtitle' => 'Building amazing web experiences',
          ],
        ],
        [
          'id' => 'post1',
          'type' => 'node.blog_post',
          'values' => [
            'title' => 'Getting Started with Headless CMS',
            'slug' => 'getting-started-headless-cms',
            'body' => '<p>This is a comprehensive guide...</p>',
            'publish_date' => '2024-01-15',
            'tags' => ['cms', 'headless', 'tutorial'],
            'featured' => TRUE,
            'hero_section' => '@hero1',
          ],
        ],
      ],
    ], JSON_PRETTY_PRINT);
  }

}
