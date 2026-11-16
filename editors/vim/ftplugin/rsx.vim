" ftplugin/rsx.vim - buffers settings and the two commands.

if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

setlocal commentstring=//\ %s
setlocal comments=://
setlocal suffixesadd=.rsx
setlocal include=^\s*include\s\+\zs"[^"]*"
setlocal define=^\s*\%(fn\|struct\|enum\|mod\)\s\+\zs\h\w*

silent! compiler rsc

command! -buffer -bar RsharpBuild call rsharp#build()
command! -buffer -bar RsharpRun call rsharp#run()

let b:undo_ftplugin = 'setlocal commentstring< comments< suffixesadd< include< define< makeprg< errorformat<'
let b:undo_ftplugin .= ' | silent! delcommand RsharpBuild'
let b:undo_ftplugin .= ' | silent! delcommand RsharpRun'
