# Editors

Three integrations, all built on the error lines the compilers already print.
Nothing here re-implements the compiler; it teaches the editor to read.

| editor | where | you get |
| --- | --- | --- |
| VS Code | `editors/vscode/` | syntax, snippets, problem matchers |
| Vim 8 | `editors/vim/` | filetype, syntax, indent, `:compiler`, two commands |
| Neovim | `editors/neovim/` | the Vim files plus Lua commands, a quickfix build, an LSP client and a lazy.nvim spec |

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

lazy.nvim. `editors/neovim/lazy.lua` is a ready spec — copy it into your
`lua/plugins/` and edit the one path at the top:

```lua
local root = vim.fn.expand('~/rsharp')

return {
  {
    dir = root .. '/editors/neovim',
    ft = { 'rsx', 'mini' },
    init = function()
      vim.filetype.add({ extension = { rsx = 'rsx', mini = 'mini' } })
      vim.opt.runtimepath:append(root .. '/editors/vim')
    end,
    config = function()
      require('rsharp').setup()
    end,
  },
}
```

The `init` half is not decoration. `ft` only fires once something has already
decided a buffer is `.rsx`, and the plugin is not on `runtimepath` until it
loads, so `ftdetect/` cannot help on its own — `vim.filetype.add` in `init` is
what breaks the circle. `runtimepath` gets `editors/vim` in the same place
because syntax and ftplugin are read at the `FileType` event, which has already
happened by the time `config` runs.

Without a plugin manager, put both directories on `runtimepath` in `init.lua`,
`editors/neovim` first:

```lua
vim.opt.runtimepath:append('~/rsharp/editors/neovim')
vim.opt.runtimepath:append('~/rsharp/editors/vim')
require('rsharp').setup()
```

`editors/neovim/ftdetect/rsx.vim` covers that path: `filetype on` sources it and
`.rsx`/`.mini` land on the right filetype with no Lua involved.

```
:RsharpBuild     " compile the current .rsx, errors into the quickfix list
:RsharpRun       " compile, then run it in a terminal split
:RsharpTest      " regress.sh, or regress.cmd on Windows
:MiniRun         " compile and run the current .mini through mini/run.sh
:RsharpLsp       " attach the language server to this buffer
```

`setup()` takes `{ rsc = ..., mini = ..., test = ..., lsp = ... }`; each one
overrides the driver that would otherwise be found by walking up from the plugin
directory. With no arguments it finds `rsc.sh`/`rsc.cmd`,
`mini/run.sh`/`mini/run.cmd` and `regress.sh`/`regress.cmd` next to the repo, so
the overrides are only for a checkout somewhere unexpected.

`.cmd` drivers on Windows go through the shell, quoted per argument, because
`cmd.exe` re-parses its own command line and mangles a bare argument list as
soon as a path contains a space. `rsc.sh` and the compiled `.exe` are spawned
directly.

The language server is not built by the plugin. `work/lsp/run.cmd` builds
`work/lsp/build/t_lspsrv.exe` and runs its suite; until that exists, `.rsx`
buffers load exactly as they did before. Once it does, opening any `.rsx` file
attaches the client, and `:RsharpLsp` attaches it by hand. `setup({ lsp = ... })`
points at a binary somewhere else.

What arrives: diagnostics from the structural scan — unterminated strings and
block comments, bracket mismatches, brackets left open at EOF — republished as
you type and emptied when the buffer is fixed; and hover over R# keywords and
types, which returns the word under the cursor and its range. Positions are
UTF-16 code units, matching the `positionEncoding` the server advertises.

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
