(function () {
  'use strict';

  const exampleFiles = {
    hello: 'hello-world.cara',
    fibonacci: 'fibonacci.cara',
    enum: 'enum-usage.cara',
    types: 'types.cara',
    'trailing-if': 'trailing-if.cara',
  };

  const selectElement = document.getElementById('exampleSelect');
  const codeElement = document.getElementById('homeExampleCode');
  const fileNameElement = document.getElementById('exampleFileName');
  if (!selectElement || !codeElement) return;

  async function loadSelectedExample() {
    const fileName = exampleFiles[selectElement.value] || exampleFiles.hello;
    if (fileNameElement) fileNameElement.textContent = fileName;

    try {
      const response = await fetch(`examples/${fileName}`);
      if (!response.ok) throw new Error(`could not load ${fileName}`);
      codeElement.textContent = (await response.text()).trimEnd();
      if (window._rehighlight) window._rehighlight();
    } catch (error) {
      codeElement.textContent = `Unable to load examples/${fileName}. Serve the site over HTTP to read it.`;
    }
  }

  selectElement.addEventListener('change', loadSelectedExample);
  loadSelectedExample();
})();
