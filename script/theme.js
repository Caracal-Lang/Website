(function () {
  'use strict';

  const storageKey = 'caracal-theme';
  const rootElement = document.documentElement;

  function saveTheme(theme) {
    try {
      localStorage.setItem(storageKey, theme);
    } catch (e) {
      /* storage can be unavailable */
    }
    // survives file:// navigation in the same tab, where localStorage is per-file
    window.name = `${storageKey}=${theme}`;
  }

  function currentTheme() {
    const attribute = rootElement.getAttribute('data-theme');
    if (attribute === 'light' || attribute === 'dark') return attribute;
    return 'dark';
  }

  function otherTheme() {
    if (currentTheme() === 'dark') {
      return 'light';
    }
    return 'dark';
  }

  const toggleButton = document.getElementById('themeToggle');
  if (!toggleButton) return;

  const label = document.getElementById('themeLabel');

  function updateLabel() {
    const nextTheme = otherTheme();
    toggleButton.setAttribute('aria-label', `Switch to ${nextTheme} theme`);
    toggleButton.setAttribute('title', `Switch to ${nextTheme} theme`);
    // the label is the theme the button switches to
    if (label) label.textContent = nextTheme.charAt(0).toUpperCase() + nextTheme.slice(1);
  }

  toggleButton.addEventListener('click', function () {
    const nextTheme = otherTheme();
    rootElement.setAttribute('data-theme', nextTheme);
    saveTheme(nextTheme);
    updateLabel();
  });

  updateLabel();
})();
