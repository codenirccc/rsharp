
if exists('current_compiler')
  finish
endif
let current_compiler = 'rsc'

let &l:errorformat =
      \ 'rsc: %f: line %l:%c: %m,' .
      \ 'rsc: %f: line %l: %m,' .
      \ 'rscb: %f: %m,' .
      \ 'rsc: %f: %m'

if !empty(rsharp#driver())
  let &l:makeprg = escape(rsharp#driver(), ' \')
endif
