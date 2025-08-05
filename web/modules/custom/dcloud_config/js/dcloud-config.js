/**
 * @file
 * JavaScript functionality for Next.js configuration page.
 */

(function (Drupal) {
  'use strict';

  /**
   * Copy text to clipboard functionality.
   */
  Drupal.behaviors.nextjsConfigCopy = {
    attach: function (context, settings) {
      // Add event listeners to copy buttons
      once('nextjs-copy', '.nextjs-config-copy-button', context).forEach(function (button) {
        button.addEventListener('click', function () {
          const targetId = this.getAttribute('data-target');
          const element = document.getElementById(targetId);
          if (element) {
            copyToClipboard(element, this);
          }
        });
      });
    }
  };

  /**
   * Copy text content to clipboard.
   *
   * @param {Element} element - The element containing text to copy.
   * @param {Element} button - The copy button element.
   */
  function copyToClipboard(element, button) {
    const text = element.textContent || element.innerText;

    if (navigator.clipboard && window.isSecureContext) {
      // Use the modern clipboard API.
      navigator.clipboard.writeText(text).then(function () {
        showCopySuccess(button);
      }).catch(function () {
        fallbackCopyText(text, button);
      });
    }
    else {
      // Fallback for older browsers.
      fallbackCopyText(text, button);
    }
  }

  /**
   * Fallback copy method for older browsers.
   *
   * @param {string} text - The text to copy.
   * @param {Element} button - The copy button element.
   */
  function fallbackCopyText(text, button) {
    const textArea = document.createElement("textarea");
    textArea.value = text;
    textArea.style.position = "fixed";
    textArea.style.left = "-999999px";
    textArea.style.top = "-999999px";
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();

    try {
      document.execCommand("copy");
      showCopySuccess(button);
    }
    catch (err) {
      console.error("Failed to copy: ", err);
      button.textContent = "❌ Failed";
      button.classList.add('nextjs-config-copy-button--error');
      setTimeout(function () {
        button.textContent = "📋 Copy";
        button.classList.remove('nextjs-config-copy-button--error');
      }, 2000);
    }

    textArea.remove();
  }

  /**
   * Show copy success feedback.
   *
   * @param {Element} button - The copy button element.
   */
  function showCopySuccess(button) {
    const originalText = button.textContent;
    button.textContent = "✅ Copied!";
    button.classList.add('nextjs-config-copy-button--success');
    setTimeout(function () {
      button.textContent = originalText;
      button.classList.remove('nextjs-config-copy-button--success');
    }, 2000);
  }

  /**
   * Generate secrets via AJAX.
   */
  Drupal.behaviors.nextjsConfigGenerateSecret = {
    attach: function (context, settings) {
      // Add event listener to generate secret button
      once('nextjs-generate-secret', '.nextjs-config-generate-button', context).forEach(function (button) {
        button.addEventListener('click', function (e) {
          e.preventDefault();
          generateSecretsAjax(button);
        });
      });
    }
  };

  /**
   * Generate secrets via AJAX call.
   *
   * @param {Element} button - The generate button element.
   */
  function generateSecretsAjax(button) {
    const form = button.closest('form');
    const formData = new FormData(form);
    
    // Show loading state
    const originalText = button.textContent;
    button.textContent = '⏳ Generating...';
    button.disabled = true;

    fetch('/nextjs-config/generate-secret-ajax', {
      method: 'POST',
      body: formData
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Update the client secret in the code block
        updateClientSecret(data.client_secret);
        
        // Show success message
        showMessage(data.message, 'success');
        
        // Reset button
        button.textContent = '✅ Generated!';
        setTimeout(function () {
          button.textContent = originalText;
          button.disabled = false;
        }, 2000);
      } else {
        // Show error message
        showMessage(data.error || 'Failed to generate secrets', 'error');
        
        // Reset button
        button.textContent = '❌ Failed';
        setTimeout(function () {
          button.textContent = originalText;
          button.disabled = false;
        }, 3000);
      }
    })
    .catch(error => {
      console.error('Error:', error);
      showMessage('Network error occurred', 'error');
      
      // Reset button
      button.textContent = '❌ Error';
      setTimeout(function () {
        button.textContent = originalText;
        button.disabled = false;
      }, 3000);
    });
  }

  /**
   * Update client secret in the code block.
   */
  function updateClientSecret(clientSecret) {
    const codeBlock = document.querySelector('.nextjs-config-code-block pre');
    if (codeBlock) {
      let content = codeBlock.textContent;
      
      // Update client secret
      content = content.replace(/DRUPAL_CLIENT_SECRET=.*$/m, `DRUPAL_CLIENT_SECRET=${clientSecret}`);
      
      codeBlock.textContent = content;
    }
  }

  /**
   * Show message to user.
   */
  function showMessage(message, type) {
    // Create message element
    const messageDiv = document.createElement('div');
    messageDiv.className = `messages messages--${type}`;
    messageDiv.innerHTML = `<p>${message}</p>`;
    
    // Insert at top of page
    const container = document.querySelector('.nextjs-config-container');
    if (container) {
      container.insertBefore(messageDiv, container.firstChild);
      
      // Auto-remove after 5 seconds
      setTimeout(function () {
        if (messageDiv.parentNode) {
          messageDiv.parentNode.removeChild(messageDiv);
        }
      }, 5000);
    }
  }

})(Drupal);
