<?php

namespace Drupal\dc_import\Form;

use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\dc_import\Service\DrupalContentImporter;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Provides a form for importing content from JSON.
 */
class ImportForm extends FormBase {

  /**
   * The Drupal content importer service.
   *
   * @var \Drupal\dc_import\Service\DrupalContentImporter
   */
  protected $contentImporter;

  /**
   * Constructs a new ImportForm.
   *
   * @param \Drupal\dc_import\Service\DrupalContentImporter $content_importer
   *   The Drupal content importer service.
   */
  public function __construct(DrupalContentImporter $content_importer) {
    $this->contentImporter = $content_importer;
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('dc_import.content_importer')
    );
  }

  /**
   * {@inheritdoc}
   */
  public function getFormId() {
    return 'dc_import_form';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state) {
    $form['description'] = [
      '#markup' => '<p>' . $this->t('Upload a JSON file to import content types, taxonomy vocabularies, and content into your Drupal site.') . '</p>',
    ];

    $form['json_file'] = [
      '#type' => 'file',
      '#title' => $this->t('JSON Import File'),
      '#description' => $this->t('Upload a JSON file containing the content to import. Maximum file size: 10 MB.'),
      '#upload_validators' => [
        'FileExtension' => ['extensions' => 'json'],
        'FileSizeLimit' => ['fileLimit' => '10M'],
      ],
    ];

    $form['json_text'] = [
      '#type' => 'textarea',
      '#title' => $this->t('Or paste JSON directly'),
      '#description' => $this->t('Paste your JSON content here if you prefer not to upload a file.'),
      '#rows' => 10,
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
    // Check if either file or text was provided.
    $files = $this->getRequest()->files->get('files', []);
    $json_text = $form_state->getValue('json_text');

    if (empty($files['json_file']) && empty($json_text)) {
      $form_state->setErrorByName('json_file', $this->t('Please either upload a JSON file or paste JSON content.'));
      return;
    }

    // Get JSON content from file or textarea.
    $json_content = '';
    if (!empty($files['json_file'])) {
      $file = $files['json_file'];
      if ($file->isValid()) {
        $json_content = file_get_contents($file->getPathname());
      }
    }
    else {
      $json_content = $json_text;
    }

    // Validate JSON.
    $data = json_decode($json_content, TRUE);
    if (json_last_error() !== JSON_ERROR_NONE) {
      $form_state->setErrorByName('json_file', $this->t('Invalid JSON: @error', [
        '@error' => json_last_error_msg(),
      ]));
      return;
    }

    // Store decoded data for submit handler.
    $form_state->set('import_data', $data);
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state) {
    $data = $form_state->get('import_data');

    try {
      $result = $this->contentImporter->import($data);

      if ($result['success']) {
        $this->messenger()->addStatus($this->t('Content imported successfully!'));

        // Show detailed results.
        if (!empty($result['content_types'])) {
          $this->messenger()->addStatus($this->t('Content types created: @count', [
            '@count' => count($result['content_types']),
          ]));
        }
        if (!empty($result['vocabularies'])) {
          $this->messenger()->addStatus($this->t('Vocabularies created: @count', [
            '@count' => count($result['vocabularies']),
          ]));
        }
        if (!empty($result['content'])) {
          $this->messenger()->addStatus($this->t('Content items created: @count', [
            '@count' => count($result['content']),
          ]));
        }
      }
      else {
        $this->messenger()->addError($this->t('Import failed: @message', [
          '@message' => $result['message'] ?? 'Unknown error',
        ]));
      }
    }
    catch (\Exception $e) {
      $this->messenger()->addError($this->t('Import error: @message', [
        '@message' => $e->getMessage(),
      ]));
      \Drupal::logger('dc_import')->error('Import error: @message', [
        '@message' => $e->getMessage(),
      ]);
    }
  }

}
