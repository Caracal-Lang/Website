(function () {
  'use strict';

  // runs before the page paints
  let themeValue = null;

  try {
    themeValue = localStorage.getItem('caracal-theme');
  } catch (e) {
    /* storage can be unavailable */
  }

  if (!themeValue) {
    // survives file:// navigation in the same tab, where localStorage is per-file
    const nameMatch = (window.name || '').match(/caracal-theme=(light|dark)/);
    if (nameMatch) themeValue = nameMatch[1];
  }

  if (!themeValue && window.matchMedia) {
    // nothing chosen yet, follow the operating system
    if (window.matchMedia('(prefers-color-scheme: light)').matches) themeValue = 'light';
  }

  if (themeValue === 'light' || themeValue === 'dark') {
    document.documentElement.setAttribute('data-theme', themeValue);
  }
})();
