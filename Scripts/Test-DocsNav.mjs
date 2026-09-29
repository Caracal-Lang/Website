// node Scripts/Test-DocsNav.mjs
//
// Exercises script/docs.js against a minimal DOM, because the scroll-spy is invisible to every
// other check: a broken one still renders, still validates, and still passes Test-Site.ps1.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, '..', 'script', 'docs.js'), 'utf8');

/* ---------- the smallest DOM this script needs ---------- */

function makeElement(tag, attributes = {}) {
  const classes = new Set();
  return {
    tag,
    parent: null,
    children: [],
    attributes,
    top: 0,
    classList: {
      toggle(name, force) {
        if (force) classes.add(name);
        else classes.delete(name);
      },
      contains: (name) => classes.has(name),
    },
    getAttribute(name) {
      return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null;
    },
    setAttribute(name, value) {
      this.attributes[name] = value;
    },
    addEventListener() {},
    getBoundingClientRect() {
      return { top: this.top };
    },
    closest(selector) {
      const wanted = selector.replace('.', '');
      let node = this;
      while (node) {
        if ((node.attributes.class || '').split(' ').includes(wanted)) return node;
        node = node.parent;
      }
      return null;
    },
    querySelectorAll(selector) {
      const out = [];
      const walk = (node) => {
        for (const child of node.children) {
          if (selector === 'a[href^="#"]' && child.tag === 'a') out.push(child);
          if (
            selector === '.docs-toc-chapter' &&
            (child.attributes.class || '').split(' ').includes('docs-toc-chapter')
          ) {
            out.push(child);
          }
          walk(child);
        }
      };
      walk(this);
      return out;
    },
  };
}

function append(parent, child) {
  child.parent = parent;
  parent.children.push(child);
  return child;
}

/* ---------- a page: two chapters, two sections each ---------- */

function buildScene() {
  const byId = new Map();
  const headings = [];

  const toc = makeElement('nav', { class: 'docs-toc', 'data-open': 'false' });
  const toggle = makeElement('button', {});
  const list = makeElement('ul', { class: 'docs-toc-list' });

  const chapters = [
    { slug: 'a-first-look', sections: ['hello-world', 'a-tour-in-one-file'] },
    { slug: 'control-flow', sections: ['while', 'trailing-if'] },
  ];

  let offset = 0;
  const linksBySlug = new Map();
  const chapterNodes = new Map();

  for (const chapter of chapters) {
    const item = append(list, makeElement('li', { class: 'docs-toc-chapter' }));
    chapterNodes.set(chapter.slug, item);

    const link = append(item, makeElement('a', { href: `#${chapter.slug}` }));
    link.hash = `#${chapter.slug}`;
    linksBySlug.set(chapter.slug, link);

    const heading = makeElement('h2', { id: chapter.slug });
    heading.top = offset;
    offset += 500;
    byId.set(chapter.slug, heading);
    headings.push(heading);

    const sectionList = append(item, makeElement('ul', { class: 'docs-toc-sections' }));
    for (const slug of chapter.sections) {
      const sectionItem = append(sectionList, makeElement('li', {}));
      const sectionLink = append(sectionItem, makeElement('a', { href: `#${slug}` }));
      sectionLink.hash = `#${slug}`;
      linksBySlug.set(slug, sectionLink);

      const sectionHeading = makeElement('h3', { id: slug });
      sectionHeading.top = offset;
      offset += 500;
      byId.set(slug, sectionHeading);
      headings.push(sectionHeading);
    }
  }

  byId.set('docsToc', toc);
  byId.set('docsTocToggle', toggle);
  byId.set('docsTocList', list);

  return { byId, headings, linksBySlug, chapterNodes, list };
}

/* ---------- run docs.js against it ---------- */

function run(scene) {
  const observed = [];
  let observerCallback = null;

  const sandbox = {
    document: {
      getElementById: (id) => scene.byId.get(id) || null,
      addEventListener() {},
    },
    window: { innerHeight: 1000 },
    Map,
    Set,
    Array,
    Math,
    decodeURIComponent,
    IntersectionObserver: class {
      constructor(callback) {
        observerCallback = callback;
      }
      observe(target) {
        observed.push(target);
      }
    },
  };

  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);

  return {
    observed,
    scrollTo(heading) {
      // put the requested heading at the top of the viewport, everything else relative to it
      const shift = heading.top;
      for (const other of scene.headings) other.top = other.top - shift;
      if (observerCallback) observerCallback([{ target: heading, isIntersecting: true }]);
    },
  };
}

/* ---------- the cases ---------- */

let failures = 0;

function check(name, condition) {
  if (condition) {
    console.log(`  ok    ${name}`);
  } else {
    console.log(`  FAIL  ${name}`);
    failures++;
  }
}

console.log('\ndocs navigation');

{
  const scene = buildScene();
  const runtime = run(scene);
  check('every heading in the contents is observed', runtime.observed.length === scene.headings.length);
}

{
  const scene = buildScene();
  const runtime = run(scene);
  runtime.scrollTo(scene.byId.get('a-tour-in-one-file'));

  check(
    'the section being read is marked current',
    scene.linksBySlug.get('a-tour-in-one-file').classList.contains('is-current')
  );
  check(
    'its chapter is opened so the section can be seen',
    scene.chapterNodes.get('a-first-look').classList.contains('is-active')
  );
  check(
    'the other chapter stays closed',
    !scene.chapterNodes.get('control-flow').classList.contains('is-active')
  );
}

{
  const scene = buildScene();
  const runtime = run(scene);
  runtime.scrollTo(scene.byId.get('control-flow'));

  check(
    'a chapter heading marks its own link current',
    scene.linksBySlug.get('control-flow').classList.contains('is-current')
  );
  check(
    'reading a chapter opens it',
    scene.chapterNodes.get('control-flow').classList.contains('is-active')
  );
  check(
    'the section marked on the previous scroll is cleared',
    !scene.linksBySlug.get('hello-world').classList.contains('is-current')
  );
}

console.log('');
if (failures > 0) {
  console.log(`docs navigation: ${failures} failure(s).`);
  process.exit(1);
}
console.log('docs navigation: all cases passed.');
