
if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

setlocal commentstring=//\ %s
setlocal comments=://
setlocal suffixesadd=.mini

command! -buffer -bar MiniRun call rsharp#minirun()

let b:undo_ftplugin = 'setlocal commentstring< comments< suffixesadd<'
let b:undo_ftplugin .= ' | silent! delcommand MiniRun'
