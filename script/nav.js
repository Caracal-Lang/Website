(function () {
  'use strict';

  const toggleButton = document.getElementById('drawerToggle');
  const drawer = document.getElementById('siteDrawer');
  const overlay = document.getElementById('drawerOverlay');
  if (!toggleButton || !drawer) return;

  function setOpen(isOpen) {
    let state = 'false';
    if (isOpen) {
      state = 'true';
    }
    drawer.setAttribute('data-open', state);
    toggleButton.setAttribute('aria-expanded', state);
    if (overlay) overlay.setAttribute('data-open', state);

    let label = 'Open menu';
    if (isOpen) {
      label = 'Close menu';
    }
    toggleButton.setAttribute('aria-label', label);
  }

  toggleButton.addEventListener('click', function () {
    setOpen(drawer.getAttribute('data-open') !== 'true');
  });

  drawer.addEventListener('click', function (event) {
    if (event.target.closest('a')) setOpen(false);
  });

  if (overlay) {
    overlay.addEventListener('click', function () {
      setOpen(false);
    });
  }

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape') return;
    if (drawer.getAttribute('data-open') !== 'true') return;
    setOpen(false);
    toggleButton.focus();
  });

  window.addEventListener('resize', function () {
    if (window.innerWidth > 800) setOpen(false);
  });
})();
