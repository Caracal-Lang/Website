// node Scripts/Test-Highlighter.mjs
//
// The tokenizer has to follow the compiler's lexer, and nothing else on the site notices when it
// stops doing so: wrong colours render perfectly well.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
// a path may be passed in to run these same cases against a different tokenizer
const target = process.argv[2] || join(here, '..', 'script', 'highlight.js');
const source = readFileSync(target, 'utf8');

const sandbox = { window: {}, document: undefined, Object, String, RegExp };
vm.createContext(sandbox);
vm.runInContext(source, sandbox);
const highlight = sandbox.window._highlightText;

let failures = 0;

function check(name, condition, detail) {
  if (condition) {
    console.log(`  ok    ${name}`);
    return;
  }
  console.log(`  FAIL  ${name}`);
  if (detail) console.log(`        ${detail}`);
  failures++;
}

// does the given text carry the given class in the output?
function classOf(code, text) {
  const html = highlight(code);
  const escaped = text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = html.match(new RegExp(`<span class="(hl-[a-z]+)">${escaped}</span>`));
  if (match) return match[1];
  return null;
}

function isPlain(code, text) {
  return classOf(code, text) === null;
}

console.log('\nhighlighter');

check('ref and init are keywords', classOf('ref x', 'ref') === 'hl-kw' && classOf('init x', 'init') === 'hl-kw');

check(
  'not, for, match and variant are not keywords',
  ['not', 'for', 'match', 'variant'].every(function (word) {
    return classOf(`${word} y`, word) !== 'hl-kw';
  }),
  'the old rules coloured all four, none of them is in the lexer'
);

check(
  'an annotation is marked and its arguments still read as code',
  classOf('#step(10)', '#step') === 'hl-prep' && classOf('#step(10)', '10') === 'hl-num'
);

check('a bare annotation is marked', classOf('#flag', '#flag') === 'hl-prep');

check(
  'a typed literal suffix stays part of the number',
  classOf("x := 82'rune;", "82'rune") === 'hl-num',
  `got ${highlight("x := 82'rune;")}`
);

check('a hex literal is a number', classOf('mask :: 0xFF00;', '0xFF00') === 'hl-num');

check(
  'a comment containing a keyword stays a comment',
  classOf('// return early if true', '// return early if true') === 'hl-cmt'
);

check(
  'a block comment containing a keyword stays a comment',
  classOf('/* def main() */', '/* def main() */') === 'hl-cmt'
);

check(
  'a string containing a comment marker stays a string',
  classOf('puts("// not a comment");', '"// not a comment"') === 'hl-str'
);

check(
  'a string containing an escaped quote is one string',
  classOf('s :: "say \\"hi\\"";', '"say \\"hi\\""') === 'hl-str'
);

check(
  'a builtin type inside an array type is a type',
  classOf('def first(values: [i32; 4]) i32', 'i32') === 'hl-type'
);

check(
  'a slice type marks its element type',
  classOf('def sum(values: [f64]) f64', 'f64') === 'hl-type'
);

check(
  'a capitalised name is a type',
  classOf('stage :: BuildStage.Typechecker;', 'BuildStage') === 'hl-type'
);

check(
  'a leading dot member access is not a namespace',
  isPlain('return .one;', 'one'),
  `got ${highlight('return .one;')}`
);

check('a leading dot method call is a call', classOf('return .one();', 'one') === 'hl-fn');

check('a call is marked', classOf('result :: fib(8);', 'fib') === 'hl-fn');

check(
  'wrapping operators do not swallow the operands',
  classOf('total = total %+ 1;', '1') === 'hl-num'
);

check(
  'the whole of a real sample round-trips its text',
  (function () {
    const sample = 'def main()\n{\n    print("Hello, World!");\n}';
    const stripped = highlight(sample)
      .replace(/<[^>]+>/g, '')
      .replace(/&quot;/g, '"')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>');
    return stripped === sample;
  })(),
  'highlighting must not lose or reorder a single character'
);

console.log('');
if (failures > 0) {
  console.log(`highlighter: ${failures} failure(s).`);
  process.exit(1);
}
console.log('highlighter: all cases passed.');
