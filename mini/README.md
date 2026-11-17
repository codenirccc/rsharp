# Mini — a compiler written in R#

`mini/` is a compiler for a small language, and the compiler itself is an R#
program. The portable core is `src/mini.rsx` (1,868 lines); the OS never leaks
into it — the core calls only the `host_*` layer, and the build concatenates
one of the two host files onto the core: `host_win.rsx` on Windows (259
lines), `host_mac.rsx` on macOS (208 lines). Two files in, one translation
unit per platform, no conditional compilation, because R# does not have it.

Mini compiles Mini source to R# IR and links a native image with the R# back
end. There is no C, no LLVM, no parser generator, no allocator in the
compiler itself.

```
prog.mini --[mini.exe, written in R#]--> prog.rsi --[rscb]--> prog.exe
```

`mini -v` prints the banner — `mini Compiler for R# 1.2`, with the tagline
`jit + aot - one file - no runtime`.

## Build and run

```
mini\build.cmd                 :: compiler for this host     -> mini\mini.exe
mini\build.cmd macos           :: cross-build the macOS image -> build\mini_mac
mini\build.sh                  :: posix twin (auto host)     -> mini/mini or mini/mini.exe
mini\build.sh macos            :: same, with the target named
mini\run.cmd mini\examples\fib.mini     :: build, then AOT fib -> fib.exe
mini\test.cmd                           :: the whole suite below
mini\test.sh                            :: the same, on posix
```

`run.cmd` and `run.sh` rebuild the compiler from source each time, so editing
`src/mini.rsx` is all it takes to change the language. `test.sh` converts
paths with `cygpath -w` when it is available: mini spawns the back end itself
with `CreateProcess` and never sees MSYS path translation.

## The three ways in

`usage: mini [--emit|--aot|--jit] file.mini [-o out]` — and
`mini -v`, and `mini < prog.mini > prog.rsi`.

With no arguments, mini reads Mini on stdin and writes IR on stdout; that is
the same as `--emit` with no `-o`.

| mode | does | output path |
| --- | --- | --- |
| `--emit` | compile to R# IR | stdout, or `-o out.rsi` |
| `--aot` | compile, write IR to a temp file, invoke the back end, delete the temp file | `-o out`, else the source stem with the host extension swapped in |
| `--jit` | like `--aot`, but into a temporary image, run it, delete the image, exit with the program's exit code | temporary, always |

`mini --jit prog.mini arg1 arg2` forwards everything after the file name to
the program. This is not a JITing back end — the same AOT writer produces a
temp image, the image is executed, and then unlinked. The back end is located
relative to the mini binary: `<its directory>/../backend/rscb` (plus `.exe`
on Windows), which is why mini lives in `mini/` next to `backend/`. Temp
files are `mini<pid>-<tag>` under `%TEMP%` or `$TMPDIR` (`/tmp` as a
fallback).

```
mini.exe < prog.mini > prog.rsi
prog.rsi --[rscb]--> prog.exe
```

## The language

Mini is i64-only. One type means the compiler never has to infer or check
anything numeric.

```
program  := fn*
fn       := 'fn' name '(' [name (',' name)*] ')' block
block    := '{' stmt* '}'
stmt     := 'let' name '=' expr ';'
          | 'var' name '=' expr ';'
          | 'print' '(' [expr (',' expr)*] ')' ';'
          | 'case' '(' expr ')' '{' arm* '}'
          | 'return' [expr] ';'
          | 'break' ';' | 'continue' ';'
          | 'if' '(' expr ')' block ('else' (block | stmt))?
          | 'while' '(' expr ')' block
          | name ('=' | '+=' | '-=' | '*=' | '/=' | '%=') expr ';'
          | expr ';'
arm      := value (',' value)* '=>' block
          | 'else' '=>' block
expr     := or
or       := and ('||' and)*
and      := cmp ('&&' cmp)*
cmp      := add (('<'|'<='|'>'|'>='|'=='|'!=') add)*
add      := mul (('+'|'-') mul)*
mul      := unary (('*'|'/'|'%') unary)*
unary    := ('-'|'!') unary | primary
primary  := number | string | name
          | name '(' [expr (',' expr)*] ')'
          | '(' expr ')'
```

- `//` starts a comment that runs to the end of the line.
- Declarations are `let` (frozen) or `var` (assignable). The compiler does not
  check mutability — assignment to a `let` is caught by the R# back end when
  it typechecks the emitted IR.
- `main` takes no parameters. Its `return` value, or 0 when it falls off the
  end, becomes the process exit code. Every other function that falls off the
  end returns 0.
- Conditions are ordinary expressions; comparisons produce 0 or 1.
- `print(x, y, ...)` writes each argument, separated by single spaces, as
  `%lld` — or `%s` when the argument is a string literal — and then a newline.
  `print()` is legal and prints just the newline.
- `abs(x)` — absolute value, one argument.
- `min(a, b)`, `max(a, b)` — two arguments.
- `puts(s)` — one string argument, returned as i64. (The helper is emitted
  only on use.)
- `putc(v)` — one argument, sent to `putchar` as i32, returned as i64.
- `len(s)` — byte count of a string literal after escapes are collapsed;
  folded at compile time.
- Reserved: the names `print abs min max puts putc len` cannot be function
  names, and nothing may start with `__mini_`. A duplicate function name is
  an error naming the name.
- String literals support exactly `\n`, `\t`, `\r`, `\\` and `\"`. Any other
  escape, a newline inside a string, or an unterminated string is a compile
  error.
- `case` evaluates its subject once into a hidden slot and compares it
  against each arm's values in order with `==`; the first match wins. Arms
  list comma-separated values; an optional `else` arm must come last.
  `break` and `continue` inside an arm act on the nearest enclosing loop.
- `val => { ... }` — every arm body is a block; there is no fallthrough.

## The s2s path — char and bool

`mini/s2s.rsx` is a source-to-source transpiler for the same language. It
reads Mini on stdin and writes R# source on stdout, so the pipeline is
`mini --[s2s.exe]--> .rsx --[rsc.exe]--> .exe`. Everything plain Mini can
compile works unchanged through it: `s2s.exe < prog.mini > prog.rsx` then
`rsc.cmd prog.rsx prog.exe` produces a native image whose behaviour matches
the plain AOT run byte for byte (see `work\s2s\run.cmd`, which runs every
`mini\examples\*.mini` through the transpiler and byte-compares against the
same `.out` files).

The point of the transpiler is the syntax plain Mini does not have:

```
'a'  '\n'  '\t'  '\r'  '\\'  '\''  '\"'  '\0'  '\x41'
true  false
```

Char literals are the byte value as an i64, so `'a' + 1` is `98`, `print('A')`
prints `65`, and comparisons on chars are ordinary integer comparisons. Bool
literals keep their names; conditions accept them directly.

Under the hood the semantics are still Mini's i64-only world. `var ok = true;`
stores `1`, `print(true)` prints `1`, `!` on an i64 is `x == 0`. The one thing
the back end actually cares about is that `if` and `while` conditions are
`bool`, so the transpiler emits real `bool` throughout R# source: comparisons
and `&&`/`||`/`!`/`true`/`false` bind as `bool`, and any int-typed condition
is wrapped in `(cond) != 0`. `char`/`bool` therefore work everywhere plain
Mini works — in loops, in `case` subjects and arms, in `return`, in
`print` arguments — without adding a second type to the compiler itself.

```
fn main() {
  var c = 'a';
  print(c);          // 97
  print(c + 1);      // 98
  print('A' < 'Z');  // 1
  var ok = true;
  if (ok) {
    print(1);        // 1
  }
  if (false) {
    print(2);
  } else {
    print(3);        // 3
  }
  return 0;
}
```

`work\s2s\charbool.mini` is the byte-compared example for this path — `run.cmd`
ends with `s2s suite: ok`. Plain `mini\test.cmd` covers the untranslated
language exactly as it always has.

On macOS there is no script twin; the same two commands work once the front
and back end are built: `mini/s2s.rsx` builds with `./rsc.sh` like any other
R# program, then `rsc.sh prog.rsx prog` links the image. The transpiler has
only been executed on this Windows host.

## Diagnostics and limits

Mini reports syntax errors as `mini: line N: <msg>` followed by the source
line and a caret under the column. The transpiler reports as
`s2s: line N: <msg>` on stderr and exits 1.

| limit | value |
| --- | --- |
| source size | 1 MB (`SRCMAX`) |
| IR output size | 32 MB (`OUTMAX`) |
| nodes per statement | 65,536 (`NMAX`, 56 bytes each) |
| functions | 4,096 (`FNMAX`) |
| lookahead | one token (saved and restored lexer state) |

The transpiler is smaller: 1 MB of source in, 1 MB of R# source out, and
512 tracked functions. A program that hits one of these limits errors out
with a line number instead of truncating silently.

## How it is put together

One token of lookahead over a 1 MB source buffer: the lexer hands out one
token at a time and `peek_kind` saves and restores the six lexer fields to
look ahead. There is no token array. Parsing is recursive descent straight
into a node pool of 65,536 entries (rewound at the top of every statement),
and the emitter walks the pool and writes IR text into the 32 MB output
buffer. Locals live in the source buffer (1 MB), the output buffer (32 MB),
the node pool (3.5 MB) and two 4,096-slot function tables (64 KB) — flat
memory, no allocator, no per-object bookkeeping. The three big buffers are
grabbed once at startup.

The portable core never names an OS symbol. Everything it needs is behind
the `host_*` names — output, stdin, file open/read/write/unlink, temp path,
arguments, self-exe path, process spawn and the current pid — and each host
implements them once: on Windows it is Win32 with explicit wide/ANSI types,
on macOS it is libSystem (`read`, `write`, `open`, `unlink`, `system`,
`getenv`, `calloc`, `_NSGetArgv`, `_NSGetExecutablePath`). On Windows the
back end is spawned with `CreateProcessA` and waited on; on macOS it is
`system(3)` with the exit status decoded from the wait status.

The generated IR is ordinary R# IR — `(program (fn …) …)` — with `(var …)`,
`(while …)`, `(if (then) (else))`, `(assign op lhs rhs)`, `(let …)` and
nested `(bin …)` expressions. `case` becomes a `(let __mini_caseK i64 …)` and
a chain of `(if (bin == (var __mini_caseK) (int M)) (then …) (else …))`s.
`abs`, `min` and `max` become calls to `mini_abs`, `mini_min` and `mini_max`,
emitted at the end of the program only when used; `puts` and `putc` go to the
C library with casts back to `i64`; `printf` is always declared.

## Footprint

Measured on this machine (2026-11-16), sizes of the binaries involved:

| binary | size |
| --- | --- |
| `mini\mini.exe` | 147,968 bytes |
| cross-built macOS image (`build/mini_mac`, Mach-O x86-64) | 148,032 bytes |
| `frontend\target\release\rsc.exe` (front end) | 528,384 bytes |
| `backend\rscb.exe` (back end) | 2,942,978 bytes |
| `build\fib.exe` (a Mini program, AOT) | 2,048 bytes |

Sizes move with edits; these are snapshots, not promises. Working set was
not measured on this host — the sizes can be checked with `dir`/`ls`, a
working set is sampled while the process runs.

## Tests

`test.cmd` builds the compiler and then, for every `examples/*.mini`:

1. `--aot` to a native binary, runs it, byte-compares against `examples/*.out`
2. `--jit` the same program, byte-compares
3. the stdin filter → IR → `rscb` link, and checks only that the link works
4. `mini -v`, and byte-checks the banner title and the tagline

A run ends with no output on success beyond the `ok <name>` lines and exits 0.
`test.sh` does the same with posix tools, with `cmp` where present and a
bash fallback otherwise. `regress.cmd` runs `mini\test.cmd` and `regress.sh`
runs `mini/test.sh`, so both already cover Mini.

The examples:

```
fib      16 lines   recursion, if, while, calls
basics   22 lines   precedence, unary minus, !, &&, ||, compound assignment
case     39 lines   arms with value lists, else arm, break and continue in an arm
control  17 lines   break and continue in one loop
primes   23 lines   nested loops, modulo, early exit through a flag
collatz  31 lines   999 Collatz chains, best-so-far tracking
```

Expected outputs are byte-compared. macOS note: the cross-built image was
checked structurally (Mach-O headers and sections) but has not been executed
on a Mac in this repository; `mini --aot`/`--jit` on macOS need a run there
to be believed.
