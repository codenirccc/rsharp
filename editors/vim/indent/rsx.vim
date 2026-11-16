
if exists('b:did_indent')
  finish
endif
let b:did_indent = 1

setlocal cindent
setlocal cinoptions+=Ls
setlocal indentkeys+=0=}
setlocal nosmartindent

let b:undo_indent = 'setlocal cindent< cinoptions< indentkeys< smartindent<'
