<?php

namespace Drupal\dcloud_chatbot\Form;

use Drupal\Core\Form\ConfigFormBase;
use Drupal\Core\Form\FormStateInterface;

/**
 * Configure DCloud Chatbot settings.
 */
class ChatbotConfigForm extends ConfigFormBase {

  /**
   * {@inheritdoc}
   */
  protected function getEditableConfigNames() {
    return ['dcloud_chatbot.settings'];
  }

  /**
   * {@inheritdoc}
   */
  public function getFormId() {
    return 'dcloud_chatbot_config_form';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state) {
    $config = $this->config('dcloud_chatbot.settings');

    $form['enabled'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('Enable Chatbot'),
      '#description' => $this->t('Check this box to enable the chatbot functionality.'),
      '#default_value' => $config->get('enabled', FALSE),
    ];

    $form['api_key'] = [
      '#type' => 'textfield',
      '#title' => $this->t('API Key'),
      '#description' => $this->t('The API key used to authenticate requests from the Next.js application.'),
      '#default_value' => $config->get('api_key', ''),
      '#required' => TRUE,
      '#maxlength' => 255,
    ];

    $form['welcome_message'] = [
      '#type' => 'textarea',
      '#title' => $this->t('Welcome Message'),
      '#description' => $this->t('The message displayed when users first interact with the chatbot.'),
      '#default_value' => $config->get('welcome_message', 'Hello! How can I help you today?'),
      '#rows' => 3,
    ];

    $form['rate_limit'] = [
      '#type' => 'number',
      '#title' => $this->t('Rate Limit (requests per minute)'),
      '#description' => $this->t('Maximum number of chat requests allowed per minute per IP address.'),
      '#default_value' => $config->get('rate_limit', 60),
      '#min' => 1,
      '#max' => 1000,
    ];

    $form['nextjs_api_url'] = [
      '#type' => 'url',
      '#title' => $this->t('Next.js API URL'),
      '#description' => $this->t('The URL of the Next.js dashboard API (e.g., https://dashboard.example.com). Leave empty to use automatic detection.'),
      '#default_value' => $config->get('nextjs_api_url', ''),
      '#maxlength' => 255,
    ];

    return parent::buildForm($form, $form_state);
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state) {
    $this->config('dcloud_chatbot.settings')
      ->set('enabled', $form_state->getValue('enabled'))
      ->set('api_key', $form_state->getValue('api_key'))
      ->set('welcome_message', $form_state->getValue('welcome_message'))
      ->set('rate_limit', $form_state->getValue('rate_limit'))
      ->set('nextjs_api_url', $form_state->getValue('nextjs_api_url'))
      ->save();

    parent::submitForm($form, $form_state);
  }

}