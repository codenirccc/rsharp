# R# and Mini

Syntax highlighting, snippets and problem matchers for the two languages in
this repository, plus the build tasks that drive them.

- `.rsx` — R#, with `fn`, `struct`, `enum`, `impl`, `mod`, `match`, loop labels,
  generics like `ptr<u8>` and `Task<T>`, and the `include "..."` directive.
- `.mini` — the small language the Mini compiler accepts.

## Install

Press `F5` in this folder to run it in a development window, or package it:

```
npx @vscode/vsce package
code --install-extension rsharp-0.1.1.vsix
```

## Diagnostics

Build with the `rsc: build current file` task (`Ctrl+Shift+B`). Errors appear in
the Problems panel because the extension contributes four problem matchers, one
per shape the compilers print:

```
rsc:  <file>: line <line>:<col>: <message>    parser and type errors
rsc:  <file>: line <line>: <message>          lexer errors (no column yet)
rsc:  <file>: <message>                       anything else about that file
rscb: <file>: <message>                       types, borrows, linking
```

The front end (`rsc`) carries a position: a column when the parser knows one, a
bare line for the lexer, which fails before a column exists. The back end
(`rscb`) covers type checks, borrow checks, unknown functions and link errors,
and names the file without a position, so those land at the top of the file.

Driver errors — `rsc: cannot write ...`, `rsc: front end not built` — are not
diagnostics and stay in the task output instead of becoming problems.

## Notes

The extension is declarative: grammars, snippets, language configuration and
problem matchers only. There is no extension host code, so there is no build
step and nothing to update when VS Code changes its API.
