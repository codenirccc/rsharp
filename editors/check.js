// Checks the editor files: valid JSON, every regex compiles, every referenced
// path exists. Run with: node editors/check.js
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');

const jsonFiles = [
  'editors/vscode/package.json',
  'editors/vscode/syntaxes/rsx.tmLanguage.json',
  'editors/vscode/syntaxes/mini.tmLanguage.json',
  'editors/vscode/snippets/rsx.json',
  'editors/vscode/snippets/mini.json',
  'editors/vscode/language-configuration-rsx.json',
  'editors/vscode/language-configuration-mini.json',
  '.vscode/tasks.json',
  '.vscode/settings.json',
];

const regexKeys = new Set([
  'match',
  'begin',
  'end',
  'regexp',
  'wordPattern',
  'increaseIndentPattern',
  'decreaseIndentPattern',
]);

let bad = 0;
let regexes = 0;
let refs = 0;

function walk(value, file, keyPath) {
  if (Array.isArray(value)) {
    value.forEach((v, i) => walk(v, file, `${keyPath}[${i}]`));
    return;
  }
  if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      if (typeof v === 'string' && regexKeys.has(k)) {
        try {
          new RegExp(v);
          regexes += 1;
        } catch (e) {
          console.log(`BAD REGEX ${file} ${keyPath}.${k}: ${e.message}`);
          console.log(`          ${v}`);
          bad += 1;
        }
      } else if (typeof v === 'string' && (k === 'path' || k === 'configuration')) {
        if (v.startsWith('./')) {
          const target = path.resolve(path.dirname(path.join(root, file)), v);
          refs += 1;
          if (!fs.existsSync(target)) {
            console.log(`MISSING ${file}: ${v}`);
            bad += 1;
          }
        }
      } else if (typeof v === 'string' && (k === 'scopeName' || k === 'language')) {
        // no-op, kept so the walker sees them
      } else {
        walk(v, file, `${keyPath}.${k}`);
      }
    }
  }
}

for (const rel of jsonFiles) {
  const full = path.join(root, rel);
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(full, 'utf8'));
  } catch (e) {
    console.log(`BAD JSON ${rel}: ${e.message}`);
    bad += 1;
    continue;
  }
  walk(parsed, rel, '');
}

console.log(`${jsonFiles.length} files, ${regexes} regexes compiled, ${refs} paths resolved, ${bad} problem(s)`);
process.exit(bad === 0 ? 0 : 1);
