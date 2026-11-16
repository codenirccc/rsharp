" Vim syntax file: R# (.rsx)
" Kept deliberately plain so it loads the same in Vim 8 and Neovim.

if exists('b:current_syntax')
  finish
endif

syn case match

" Strings and comments come first so keywords inside them stay plain.
syn region rsxString start=+"+ skip=+\\\\\|\\"+ end=+"+ contains=rsxEscape
syn match rsxEscape '\\\_.' contained
syn region rsxComment start='/\*' end='\*/' contains=@Spell
syn match rsxComment '//.*$' contains=@Spell

syn match rsxNumber '\<0[xX][0-9a-fA-F_]\+\>'
syn match rsxNumber '\<0[bB][01_]\+\>'
syn match rsxNumber '\<\d[\d_]*\(\.\d[\d_]*\)\?\([eE][+-]\?\d\+\)\?\>'

" A label is a quote, a name and a colon: 'outer: while (n > 0)
syn match rsxLabel "'\h\w*\ze\s*:"

" Defined before the keywords, so `if (` keeps the keyword colour.
syn match rsxCall '\<[a-z_]\w*\ze\s*('

syn keyword rsxKeyword let var return if else while loop for in break continue match unsafe as end
syn keyword rsxModifier mut self
syn keyword rsxStorage fn struct enum impl mod static const extern include
syn keyword rsxType i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool void ptr Task Box
syn keyword rsxBoolean true false null

syn match rsxFuncName '\<fn\s\+\zs\h\w*'
syn match rsxFuncName '\<struct\s\+\zs\h\w*'
syn match rsxFuncName '\<enum\s\+\zs\h\w*'
syn match rsxFuncName '\<impl\s\+\zs\h\w*'
syn match rsxFuncName '\<mod\s\+\zs\h\w*'

syn match rsxTypeName '\<\u\w*\>'
syn match rsxOperator '[+\-*/%=<>!&|^~]'
syn match rsxDelim '[](){}[\],;:]'

hi def link rsxComment  Comment
hi def link rsxString   String
hi def link rsxEscape   SpecialChar
hi def link rsxNumber   Number
hi def link rsxLabel    Label
hi def link rsxCall     Function
hi def link rsxKeyword  Keyword
hi def link rsxModifier StorageClass
hi def link rsxStorage  Structure
hi def link rsxType     Type
hi def link rsxTypeName Type
hi def link rsxBoolean  Boolean
hi def link rsxFuncName Function
hi def link rsxOperator Operator
hi def link rsxDelim    Delimiter

let b:current_syntax = 'rsx'
