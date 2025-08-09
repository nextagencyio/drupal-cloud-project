/**
 * @file
 * DCloud Chatbot JavaScript functionality.
 */

(function (Drupal, drupalSettings) {
  'use strict';

  /**
   * DCloud Chatbot behavior.
   */
  Drupal.behaviors.dcloudChatbot = {
    attach: function (context, settings) {
      const container = context.querySelector('#dcloud-chatbot-container');
      if (!container || container.dataset.processed) {
        return;
      }

      container.dataset.processed = 'true';

      const chatbot = new DCloudChatbot(container, settings.dcloudChatbot || {});
      chatbot.init();
    }
  };

  /**
   * DCloud Chatbot class.
   */
  function DCloudChatbot(container, settings) {
    this.container = container;
    this.settings = Object.assign({
      enabled: false,
      buttonPosition: 'bottom-right',
      buttonColor: '#007cba',
      showOnMobile: true,
      triggerDelay: 0,
      welcomeMessage: 'Hello! How can I help you today?',
      apiEndpoint: '/api/chat'
    }, settings);

    this.isOpen = false;
    this.messageHistory = [];

    // DOM elements
    this.trigger = container.querySelector('#dcloud-chatbot-trigger');
    this.panel = container.querySelector('#dcloud-chatbot-panel');
    this.closeBtn = container.querySelector('#dcloud-chatbot-close');
    this.form = container.querySelector('#dcloud-chatbot-form');
    this.input = container.querySelector('#dcloud-chatbot-input');
    this.messages = container.querySelector('#dcloud-chatbot-messages');
    this.loading = container.querySelector('#dcloud-chatbot-loading');
    this.sendBtn = container.querySelector('.dcloud-chatbot-send');
    this.backdrop = document.querySelector('#dcloud-chatbot-backdrop');
  }

  DCloudChatbot.prototype.init = function () {
    if (!this.settings.enabled) {
      console.log('DCloud Chatbot: Not enabled, skipping initialization');
      return;
    }

    console.log('DCloud Chatbot: Initializing...', this.settings);

    // Initialize loading indicator - detach from DOM initially
    if (this.loading && this.loading.parentNode) {
      this.loading.parentNode.removeChild(this.loading);
      this.loading.setAttribute('aria-hidden', 'true');
      this.loading.style.display = 'none';
    }

    this.bindEvents();
    this.setupAutoTrigger();
    this.updateWelcomeTime();
  };

  DCloudChatbot.prototype.bindEvents = function () {
    // Trigger button
    this.trigger.addEventListener('click', (e) => {
      e.preventDefault();
      this.toggle();
    });

    // Close button
    this.closeBtn.addEventListener('click', (e) => {
      e.preventDefault();
      this.close();
    });

    // Form submission
    this.form.addEventListener('submit', (e) => {
      e.preventDefault();
      this.sendMessage();
    });

    // Input events
    this.input.addEventListener('keypress', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        this.sendMessage();
      }
    });

    // Close on escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.isOpen) {
        this.close();
      }
    });

    // Close when clicking backdrop
    if (this.backdrop) {
      this.backdrop.addEventListener('click', (e) => {
        if (this.isOpen) {
          this.close();
        }
      });
    }
  };

  DCloudChatbot.prototype.setupAutoTrigger = function () {
    if (this.settings.triggerDelay > 0) {
      setTimeout(() => {
        if (!this.isOpen) {
          this.open();
        }
      }, this.settings.triggerDelay);
    }
  };

  DCloudChatbot.prototype.updateWelcomeTime = function () {
    const welcomeTime = this.messages.querySelector('.dcloud-chatbot-welcome .message-time');
    if (welcomeTime) {
      welcomeTime.textContent = this.formatTime(new Date());
    }
  };

  DCloudChatbot.prototype.toggle = function () {
    if (this.isOpen) {
      this.close();
    } else {
      this.open();
    }
  };

  DCloudChatbot.prototype.open = function () {
    this.panel.classList.add('open');
    this.panel.setAttribute('aria-hidden', 'false');
    this.isOpen = true;

    // Show backdrop
    if (this.backdrop) {
      this.backdrop.classList.add('show');
      this.backdrop.setAttribute('aria-hidden', 'false');
    }

    // Focus input
    setTimeout(() => {
      this.input.focus();
    }, 400);

    // Update trigger button
    this.trigger.setAttribute('aria-expanded', 'true');
  };

  DCloudChatbot.prototype.close = function () {
    this.panel.classList.remove('open');
    this.panel.setAttribute('aria-hidden', 'true');
    this.isOpen = false;

    // Hide backdrop
    if (this.backdrop) {
      this.backdrop.classList.remove('show');
      this.backdrop.setAttribute('aria-hidden', 'true');
    }

    // Update trigger button
    this.trigger.setAttribute('aria-expanded', 'false');
    this.trigger.focus();
  };

  DCloudChatbot.prototype.sendMessage = function () {
    const message = this.input.value.trim();
    if (!message || this.sendBtn.disabled) {
      return;
    }

    // Add user message to UI
    this.addMessage(message, 'user');

    // Clear input and disable send button
    this.input.value = '';
    this.setSendingState(true);

    // Send to API
    this.callChatAPI(message)
      .then(response => {
        this.addMessage(response.response, 'bot');
      })
      .catch(error => {
        console.error('Chat API error:', error);
        this.addMessage('Sorry, I encountered an error. Please try again later.', 'bot', true);
      })
      .finally(() => {
        this.setSendingState(false);
        this.input.focus();
      });
  };

  DCloudChatbot.prototype.addMessage = function (content, sender, isError = false) {
    const messageDiv = document.createElement('div');
    messageDiv.className = `dcloud-chatbot-message ${sender}-message${isError ? ' error-message' : ''}`;

    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content';
    
    // Render markdown for bot messages, plain text for user messages
    if (sender === 'bot') {
      contentDiv.innerHTML = this.parseMarkdown(content);
    } else {
      contentDiv.textContent = content;
    }

    const timeDiv = document.createElement('div');
    timeDiv.className = 'message-time';
    timeDiv.textContent = this.formatTime(new Date());

    messageDiv.appendChild(contentDiv);
    messageDiv.appendChild(timeDiv);

    this.messages.appendChild(messageDiv);

    // Scroll to bottom
    this.messages.scrollTop = this.messages.scrollHeight;

    // Store in history
    this.messageHistory.push({
      content: content,
      sender: sender,
      timestamp: Date.now(),
      isError: isError
    });
  };

  DCloudChatbot.prototype.setSendingState = function (sending) {
    this.sendBtn.disabled = sending;
    this.input.disabled = sending;

    if (sending) {
      this.showLoading();
    } else {
      this.hideLoading();
    }
  };

  DCloudChatbot.prototype.showLoading = function () {
    console.log('DCloud Chatbot: Showing loading');
    if (this.loading) {
      // Add loading indicator to messages area
      this.messages.appendChild(this.loading);
      this.loading.setAttribute('aria-hidden', 'false');
      this.loading.style.display = 'block';
      
      // Scroll to bottom to show loading
      this.messages.scrollTop = this.messages.scrollHeight;
    }
  };

  DCloudChatbot.prototype.hideLoading = function () {
    console.log('DCloud Chatbot: Hiding loading');
    if (this.loading && this.loading.parentNode === this.messages) {
      this.loading.setAttribute('aria-hidden', 'true');
      this.loading.style.display = 'none';
      
      // Remove from messages area
      this.messages.removeChild(this.loading);
    }
  };

  DCloudChatbot.prototype.callChatAPI = function (message) {
    // Call the local Drupal API endpoint
    return fetch('/api/chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: message,
        context: {
          spaceId: this.getSpaceId(),
          timestamp: Date.now(),
        }
      })
    })
      .then(response => {
        if (!response.ok) {
          return response.json().then(errorData => {
            throw new Error(errorData.error || `HTTP error! status: ${response.status}`);
          }).catch(() => {
            throw new Error(`HTTP error! status: ${response.status}`);
          });
        }
        return response.json();
      })
      .then(data => {
        if (data.error) {
          throw new Error(data.error);
        }
        return data;
      });
  };

  // Helper method to extract space ID from URL or configuration
  DCloudChatbot.prototype.getSpaceId = function () {
    // Try to get from drupalSettings first
    if (drupalSettings.dcloudChatbot && drupalSettings.dcloudChatbot.spaceId) {
      return drupalSettings.dcloudChatbot.spaceId;
    }

    // Try to extract from URL pattern (e.g., subdomain or path)
    const hostname = window.location.hostname;
    const parts = hostname.split('.');

    // If it's a subdomain pattern like "spacename.domain.com"
    if (parts.length >= 3) {
      return parts[0]; // Return the subdomain as space identifier
    }

    // Fallback: return the full hostname
    return hostname;
  };

  // Helper method to determine Next.js API URL
  DCloudChatbot.prototype.getNextjsApiUrl = function () {
    // In development, the Next.js app typically runs on localhost:3000
    // In production, this should be configured via drupalSettings
    if (drupalSettings.dcloudChatbot && drupalSettings.dcloudChatbot.nextjsApiUrl) {
      return drupalSettings.dcloudChatbot.nextjsApiUrl;
    }

    // Development fallback
    if (window.location.hostname.includes('localhost') || window.location.hostname.includes('127.0.0.1')) {
      return 'http://localhost:3333';
    }

    // Production fallback - assume same domain but different port or subdomain
    return 'https://dashboard.' + window.location.hostname.replace(/^[^.]+\./, '');
  };

  DCloudChatbot.prototype.parseMarkdown = function (text) {
    // Escape HTML to prevent XSS
    text = text.replace(/&/g, '&amp;')
               .replace(/</g, '&lt;')
               .replace(/>/g, '&gt;')
               .replace(/"/g, '&quot;')
               .replace(/'/g, '&#039;');

    // Parse markdown elements
    // Bold text **text**
    text = text.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
    
    // Italic text *text*
    text = text.replace(/\*(.*?)\*/g, '<em>$1</em>');
    
    // Code `code`
    text = text.replace(/`(.*?)`/g, '<code>$1</code>');
    
    // Headers (simple # support)
    text = text.replace(/^### (.*$)/gim, '<h3>$1</h3>');
    text = text.replace(/^## (.*$)/gim, '<h2>$1</h2>');
    text = text.replace(/^# (.*$)/gim, '<h1>$1</h1>');
    
    // Links [text](url)
    text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
    
    // Process lists more carefully
    const lines = text.split('<br>');
    let result = [];
    let inList = false;
    let listType = null;
    
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i].trim();
      
      // Check if this is a list item
      const ulMatch = line.match(/^\* (.*)$/);
      const olMatch = line.match(/^\d+\. (.*)$/);
      
      if (ulMatch) {
        // Unordered list item
        if (!inList || listType !== 'ul') {
          if (inList) {
            result.push(`</${listType}>`);
          }
          result.push('<ul>');
          listType = 'ul';
          inList = true;
        }
        result.push(`<li>${ulMatch[1]}</li>`);
      } else if (olMatch) {
        // Ordered list item
        if (!inList || listType !== 'ol') {
          if (inList) {
            result.push(`</${listType}>`);
          }
          result.push('<ol>');
          listType = 'ol';
          inList = true;
        }
        result.push(`<li>${olMatch[1]}</li>`);
      } else {
        // Not a list item
        if (inList) {
          result.push(`</${listType}>`);
          inList = false;
          listType = null;
        }
        if (line) {
          result.push(line);
        }
      }
    }
    
    // Close any open list
    if (inList) {
      result.push(`</${listType}>`);
    }
    
    text = result.join('<br>');
    
    return text;
  };

  DCloudChatbot.prototype.formatTime = function (date) {
    return date.toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  // Export for potential external use
  window.DCloudChatbot = DCloudChatbot;

})(Drupal, drupalSettings);
