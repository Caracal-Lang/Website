(function () {
  'use strict';

  const keywords = [
    'and',
    'break',
    'def',
    'else',
    'enum',
    'false',
    'if',
    'init',
    'new',
    'or',
    'ref',
    'return',
    'skip',
    'true',
    'type',
    'while',
  ];

  const builtinTypes = [
    'bool',
    'cstring',
    'f32',
    'f64',
    'i16',
    'i32',
    'i64',
    'i8',
    'rawptr',
    'rune',
    'string',
    'u16',
    'u32',
    'u64',
    'u8',
    'void',
  ];

  // literal with explicit type: 42'i32, 200'u8, 82'rune
  const typeSuffix = '(?:\\u0027[A-Za-z]\\w*)?';

  const scanner = new RegExp(
    [
      '(?<comment>/\\*[\\s\\S]*?\\*/|//[^\\n]*)',
      '(?<string>"(?:[^"\\\\\\n]|\\\\.)*")',
      '(?<annotation>#[A-Za-z_]\\w*)',
      '(?<number>\\b0[xX][0-9a-fA-F_]+' +
        typeSuffix +
        '|\\b\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?' +
        typeSuffix +
        ')',
      '(?<keyword>\\b(?:' + keywords.join('|') + ')\\b)',
      '(?<builtin>\\b(?:' + builtinTypes.join('|') + ')\\b)',
      '(?<usertype>\\b[A-Z]\\w*\\b)',
      '(?<call>\\b[A-Za-z_]\\w*(?=\\s*\\())',
    ].join('|'),
    'g'
  );

  const classByGroup = {
    comment: 'hl-cmt',
    string: 'hl-str',
    annotation: 'hl-prep',
    number: 'hl-num',
    keyword: 'hl-kw',
    builtin: 'hl-type',
    usertype: 'hl-type',
    call: 'hl-fn',
  };

  function escapeHtml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function matchedGroup(groups) {
    const names = Object.keys(classByGroup);
    for (let index = 0; index < names.length; index++) {
      if (groups[names[index]] !== undefined) return names[index];
    }
    return null;
  }

  function highlightText(input) {
    const text = String(input).replace(/\r\n?/g, '\n');
    let html = '';
    let cursor = 0;

    scanner.lastIndex = 0;
    let match = scanner.exec(text);
    while (match !== null) {
      const group = matchedGroup(match.groups);
      if (group) {
        if (match.index > cursor) html += escapeHtml(text.slice(cursor, match.index));
        html += '<span class="' + classByGroup[group] + '">' + escapeHtml(match[0]) + '</span>';
        cursor = match.index + match[0].length;
      }
      match = scanner.exec(text);
    }

    if (cursor < text.length) html += escapeHtml(text.slice(cursor));
    return html;
  }

  function rehighlightCodeBlocks(selector) {
    const blocks = document.querySelectorAll(selector || 'pre code.language-caracal');
    blocks.forEach(function (block) {
      block.innerHTML = highlightText(block.textContent || '');
    });
  }

  window._highlightText = highlightText;
  window._rehighlight = rehighlightCodeBlocks;

  if (typeof document !== 'undefined' && document.querySelectorAll) {
    rehighlightCodeBlocks();
  }
})();
