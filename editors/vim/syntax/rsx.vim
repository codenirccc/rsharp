
if exists('b:current_syntax')
  finish
endif

syn case match

syn region rsxString start=+"+ skip=+\\\\\|\\"+ end=+"+ contains=rsxEscape
syn match rsxEscape '\\\_.' contained
syn region rsxComment start='/\*' end='\*/' contains=@Spell
syn match rsxComment '//.*$' contains=@Spell

syn match rsxNumber '\<0[xX][0-9a-fA-F_]\+\>'
syn match rsxNumber '\<0[bB][01_]\+\>'
syn match rsxNumber '\<\d[\d_]*\(\.\d[\d_]*\)\?\([eE][+-]\?\d\+\)\?\>'

syn match rsxLabel "'\h\w*\ze\s*:"

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
