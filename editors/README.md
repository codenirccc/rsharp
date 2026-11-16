# Editors

Three integrations, all built on the error lines the compilers already print.
Nothing here re-implements the compiler; it teaches the editor to read.

| editor | where | you get |
| --- | --- | --- |
| VS Code | `editors/vscode/` | syntax, snippets, problem matchers |
| Vim 8 | `editors/vim/` | filetype, syntax, indent, `:compiler`, two commands |
| Neovim | `editors/neovim/` | the Vim files plus Lua commands and a quickfix build |

The repo itself carries `.vscode/tasks.json`, so building and running from a
fresh clone works with no extension installed at all.

## VS Code

Open `editors/vscode/` and press `F5`. That launches an Extension Development
Host with the extension loaded, which is the quickest way to see it.

To install it properly:

```
cd editors/vscode
npx @vscode/vsce package
code --install-extension rsharp-0.1.1.vsix
```

It is declarative — grammars, snippets, language configuration and problem
matchers, no extension host code — so there is nothing to build.

The extension carries the R# mark: `editors/vscode/icon.png` is the 128×128 PNG
VS Code wants for the `icon` field, rendered from the repository's `logo.jpg`,
which stays the source of truth. That is the image in the Extensions view and on
the marketplace tile; it has to be a PNG of exactly that size, which is why the
JPG is not referenced directly. The README in the repo shows the logo, the
extension README does not — vsce refuses to package a relative image in a README
unless the `repository` field or `--baseImagesUrl` gives it something to rewrite
against.

`Ctrl+Shift+B` builds the current `.rsx` and turns

```
rsc: C:\work\demo.rsx: line 7:12: expected ';', found '}'
```

into a squiggle on line 7, column 12. The task in `.vscode/tasks.json` carries
the matcher inline, so it works before the extension is installed.

## Vim 8

Native packages, no plugin manager:

```
mkdir -p ~/.vim/pack/rsharp/start
ln -s /path/to/rsharp/editors/vim ~/.vim/pack/rsharp/start/rsharp
```

vim-plug:

```vim
Plug '/path/to/rsharp', {'rtp': 'editors/vim'}
```

Then, per buffer:

```
:RsharpBuild     " :make on the current file, errors into the quickfix list
:RsharpRun       " build, then run the result
```

`:RsharpBuild` goes through `:make`, so `:copen`, `:cn` and `:cp` behave the way
you expect. The driver is `rsc.sh` or `rsc.cmd` from `$PATH`; if it lives
somewhere else:

```vim
let g:rsharp_rsc = '/path/to/rsharp/rsc.sh'
```

Also available: `:setlocal include` is wired to `include "..."`, so `gf` on an
include line opens the right file, and `:setlocal define` lets `[i` find
`fn`/`struct`/`enum`/`mod` definitions.

## Neovim

lazy.nvim:

```lua
{
  dir = '~/rsharp/editors/neovim',
  ft = { 'rsx', 'mini' },
  config = function()
    vim.opt.rtp:append('~/rsharp/editors/vim') -- syntax, ftplugin, indent
    require('rsharp').setup({ rsc = '~/rsharp/rsc.sh' })
  end,
}
```

`setup()` with no arguments finds the driver next to the repo, so the explicit
path is only needed when the repo is somewhere unexpected.

```
:RsharpBuild     " compile the current .rsx, errors into the quickfix list
:RsharpRun       " compile, then run it in a terminal split
:RsharpTest      " run regress.sh (every example, then the Mini suite)
:MiniRun         " compile and run the current .mini through mini/run.sh
```

`:RsharpBuild` fills the quickfix list directly, so `:copen` and `:cnext` work
without an `errorformat`; the Vim files still set one for `:make` users.

## The three lines everything parses

```
rsc: <file>: line <line>:<col>: <message>   parser
rsc: <file>: line <line>: <message>         lexer
rscb: <file>: <message>                     back end
```

`rsc` is the front end and carries a position: a column when the parser has one,
a bare line for lexer errors, which fail before a column exists. `rscb` is the
back end — type checks, borrow checks, unknown functions, link errors — and names
the file without a line, so editors place those problems at the top of the file.
Driver errors like `rsc: cannot write ...` are not diagnostics, and every one of
these integrations ignores them.
