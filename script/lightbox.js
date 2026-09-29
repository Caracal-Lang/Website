(function () {
  'use strict';

  const triggers = document.querySelectorAll('.image-zoom');
  if (triggers.length === 0) return;

  let overlay = null;
  let overlayImage = null;
  let closeButton = null;
  let lastTrigger = null;

  function build() {
    overlay = document.createElement('div');
    overlay.className = 'image-viewer';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'Image viewer');
    overlay.hidden = true;

    closeButton = document.createElement('button');
    closeButton.type = 'button';
    closeButton.className = 'image-viewer-close';
    closeButton.setAttribute('aria-label', 'Close image');
    closeButton.textContent = '×';

    overlayImage = document.createElement('img');
    overlayImage.className = 'image-viewer-image';
    overlayImage.alt = '';

    overlay.appendChild(closeButton);
    overlay.appendChild(overlayImage);
    document.body.appendChild(overlay);

    closeButton.addEventListener('click', close);
    overlay.addEventListener('click', function (event) {
      if (event.target === overlay) close();
    });
  }

  function open(trigger) {
    if (!overlay) build();

    lastTrigger = trigger;
    overlayImage.setAttribute('src', trigger.getAttribute('data-full'));
    overlayImage.setAttribute('alt', trigger.getAttribute('data-alt') || '');
    overlay.hidden = false;
    document.body.classList.add('image-viewer-open');
    closeButton.focus();
  }

  function close() {
    if (!overlay || overlay.hidden) return;

    overlay.hidden = true;
    overlayImage.setAttribute('src', '');
    overlayImage.setAttribute('alt', '');
    document.body.classList.remove('image-viewer-open');
    if (lastTrigger) lastTrigger.focus();
  }

  triggers.forEach(function (trigger) {
    trigger.addEventListener('click', function () {
      open(trigger);
    });
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') {
      close();
      return;
    }
    // the viewer has one control, tab stays on it
    if (event.key === 'Tab' && overlay && !overlay.hidden) {
      event.preventDefault();
      closeButton.focus();
    }
  });
})();
