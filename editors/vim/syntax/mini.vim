
if exists('b:current_syntax')
  finish
endif

syn case match

syn match miniComment '//.*$' contains=@Spell

syn match miniNumber '\<\d\+\>'

syn keyword miniKeyword let var return if else while break continue
syn keyword miniBuiltin print
syn keyword miniBoolean true false

syn match miniFuncName '\<fn\s\+\zs\h\w*'
syn match miniCall '\<[a-z_]\w*\ze\s*('
syn match miniOperator '[+\-*/%=<>!&|]'
syn match miniDelim '[(){},;]'

hi def link miniComment  Comment
hi def link miniNumber   Number
hi def link miniKeyword  Keyword
hi def link miniBuiltin  Function
hi def link miniBoolean  Boolean
hi def link miniFuncName Function
hi def link miniCall     Function
hi def link miniOperator Operator
hi def link miniDelim    Delimiter

let b:current_syntax = 'mini'
