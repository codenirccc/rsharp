
function! rsharp#driver() abort
  if exists('g:rsharp_rsc') && !empty(g:rsharp_rsc)
    return expand(g:rsharp_rsc)
  endif
  for name in ['rsc.sh', 'rsc.cmd']
    if executable(name)
      return name
    endif
  endfor
  echohl ErrorMsg
  echomsg 'rsharp: no driver found - set g:rsharp_rsc to rsc.sh or rsc.cmd'
  echohl None
  return ''
endfunction

function! rsharp#mini() abort
  if exists('g:rsharp_mini') && !empty(g:rsharp_mini)
    return expand(g:rsharp_mini)
  endif
  return 'mini/run.sh'
endfunction

function! rsharp#out(file) abort
  let out = fnamemodify(a:file, ':p:r')
  return has('win32') ? out . '.exe' : out
endfunction

function! rsharp#build(...) abort
  let file = a:0 ? a:1 : expand('%:p')
  let drv = rsharp#driver()
  if empty(drv)
    return
  endif
  let &l:makeprg = escape(drv, ' \')
  execute 'make ' . shellescape(file)
endfunction

function! rsharp#run(...) abort
  let file = a:0 ? a:1 : expand('%:p')
  let drv = rsharp#driver()
  if empty(drv)
    return
  endif
  execute '!' . shellescape(drv) . ' ' . shellescape(file)
  if v:shell_error
    echohl ErrorMsg
    echomsg 'rsharp: build failed'
    echohl None
    return
  endif
  execute '!' . shellescape(rsharp#out(file))
endfunction

function! rsharp#minirun(...) abort
  let file = a:0 ? a:1 : expand('%:p')
  let drv = rsharp#mini()
  if executable(drv)
    execute '!' . shellescape(drv) . ' ' . shellescape(file)
  else
    echohl ErrorMsg
    echomsg 'rsharp: set g:rsharp_mini to the path of mini/run.sh'
    echohl None
  endif
endfunction
