(function () {
  'use strict';

  const tableOfContents = document.getElementById('docsToc');
  const toggleButton = document.getElementById('docsTocToggle');
  const list = document.getElementById('docsTocList');
  if (!tableOfContents || !toggleButton || !list) return;

  /* ---------- the narrow-width disclosure ---------- */

  function setOpen(isOpen) {
    let state = 'false';
    if (isOpen) {
      state = 'true';
    }
    tableOfContents.setAttribute('data-open', state);
    toggleButton.setAttribute('aria-expanded', state);
  }

  toggleButton.addEventListener('click', function () {
    setOpen(tableOfContents.getAttribute('data-open') !== 'true');
  });

  list.addEventListener('click', function () {
    setOpen(false);
  });

  /* ---------- which chapter and section are in view ---------- */

  const links = Array.prototype.slice.call(list.querySelectorAll('a[href^="#"]'));
  const entriesByHeading = new Map();

  links.forEach(function (link) {
    const heading = document.getElementById(decodeURIComponent(link.hash.slice(1)));
    if (heading) entriesByHeading.set(heading, link);
  });

  if (entriesByHeading.size === 0) return;

  // Array.from, not slice.call: a Map iterator has no length
  const headingsInOrder = Array.from(entriesByHeading.keys());
  const visibleHeadings = new Set();

  function markCurrent() {
    let current = null;

    headingsInOrder.forEach(function (heading) {
      if (!current && visibleHeadings.has(heading)) current = heading;
    });

    // nothing intersects between two headings
    // fall back to the last one passed
    if (!current) {
      const cutoff = window.innerHeight * 0.3;
      headingsInOrder.forEach(function (heading) {
        if (heading.getBoundingClientRect().top <= cutoff) current = heading;
      });
    }

    entriesByHeading.forEach(function (link, heading) {
      link.classList.toggle('is-current', heading === current);
    });

    // only the active chapter shows its sections
    const currentLink = entriesByHeading.get(current);
    let currentChapter = null;
    if (currentLink) currentChapter = currentLink.closest('.docs-toc-chapter');

    list.querySelectorAll('.docs-toc-chapter').forEach(function (chapter) {
      chapter.classList.toggle('is-active', chapter === currentChapter);
    });
  }

  const observer = new IntersectionObserver(
    function (records) {
      records.forEach(function (record) {
        if (record.isIntersecting) visibleHeadings.add(record.target);
        else visibleHeadings.delete(record.target);
      });
      markCurrent();
    },
    { rootMargin: '-72px 0px -70% 0px' }
  );

  headingsInOrder.forEach(function (heading) {
    observer.observe(heading);
  });

  markCurrent();
})();
