<?php

namespace Drupal\dcloud_chatbot\Form;

use Drupal\Core\Form\ConfigFormBase;
use Drupal\Core\Form\FormStateInterface;

/**
 * Configure Drupal Cloud Chatbot settings.
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



    $form['api_url'] = [
      '#type' => 'url',
      '#title' => $this->t('Drupal Cloud Chatbot API URL'),
      '#description' => $this->t('The URL endpoint for communicating with Drupal Cloud\'s centralized AI system. This connects your site\'s chatbot to our intelligent response engine.'),
      '#default_value' => $config->get('api_url', 'http://host.docker.internal:3333/api/chatbot'),
      '#maxlength' => 255,
      '#placeholder' => 'http://host.docker.internal:3333/api/chatbot',
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
      ->set('api_url', $form_state->getValue('api_url'))
      ->save();

    parent::submitForm($form, $form_state);
  }

}
