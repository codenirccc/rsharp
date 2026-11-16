" compiler/rsc.vim - errorformat for the rsc driver.
" Loaded by ftplugin/rsx.vim through :compiler rsc.

if exists('current_compiler')
  finish
endif
let current_compiler = 'rsc'

" rsc: C:\path\file.rsx: line 12:7: expected ';'      <- parser, has a column
" rsc: C:\path\file.rsx: line 12: unterminated string  <- lexer, line only
" rscb: C:\path\file.rsx: fn main: type mismatch in '+': i32 and i64
let &l:errorformat =
      \ 'rsc: %f: line %l:%c: %m,' .
      \ 'rsc: %f: line %l: %m,' .
      \ 'rscb: %f: %m,' .
      \ 'rsc: %f: %m'

if !empty(rsharp#driver())
  let &l:makeprg = escape(rsharp#driver(), ' \')
endif
