# R#

<img src="logo.jpg" alt="R# logo" width="150" align="right">

A small systems language with memory safety proven at compile time and nothing
paid at runtime. Explicit integer widths, references, owned heap boxes,
monomorphised generics, structs by value, arrays, compile-time constants,
whole-program inlining. Two halves: the front end is Rust, the back end is
OCaml — and the back end emits machine code and writes the executable itself.
No C, no gcc, no assembler, no linker, no CRT.

```
  .rsx  --[rsc, Rust]-->  .rsi  --[rscb, OCaml]-->  .exe    PE32+ image, Win64
          lex + parse        check + fold + emit      .out   Mach-O image, SysV
```

Two targets, one back end. `-t windows` writes a PE32+ image for x86-64 Windows;
`-t macos` writes an x86-64 Mach-O for macOS. Both come out of `cg.ml`; the
calling convention and the container are the only things that change.

The IR between the halves is a plain s-expression text file. You can read it,
edit it, feed it to the back end by hand, or write your own front end against
it. That was the point of cutting the compiler in two.

Accepted ahead of time: this is an AOT compiler, not a JIT. It compiles to an
executable and stops. The one JIT-shaped entry point in the repo is
`mini --jit`, and it is a convenience, not a different back end — it
AOT-compiles to a temporary image, runs it, and deletes the image. An
in-process JIT would need `VirtualAlloc` and a runtime that pure OCaml on
Windows cannot reach; the honest shape of "no gcc" here is a native code
generator plus a hand-written PE linker, which is what `pe.ml` is.

## Build

Windows wants Rust and the msys64 UCRT64 OCaml. macOS and Linux want Rust and an
`ocamlopt` on `PATH` — Homebrew, MacPorts or opam, all the same. Nothing else.

On Windows:

```
.\build.cmd
```

`build.cmd` is the entry point; it reads `build.ps1` and runs it, because
PowerShell refuses to execute a script whose path contains `[` — and this
repository lives in a directory called `ms[r`. From a path without brackets,
`.\build.ps1` is the same script and takes `-Clean` directly. `build.cmd -Clean`
does the same from here.

Or by hand:

```
cd frontend && cargo build --release
cd ../backend && ./build.sh
cd ../cdc && cargo build --release
```

`backend/build.sh` is plain `ocamlopt` over fifteen modules, no dune and no
findlib. On Windows it reads the stdlib from `/ucrt64/lib/ocaml`; on macOS and
Linux it asks `ocamlopt -where`. Override either with `OCAMLLIB=...`.

On macOS and Linux the same three steps are one script:

```
./build.sh
./build.sh -Clean
```

It picks up whatever `ocamlopt` is on `PATH` — Homebrew, MacPorts or opam all
work — and writes `backend/rscb` without the `.exe`. `build.sh` is a plain
bash script, so a fresh checkout may need `chmod +x build.sh rsc.sh regress.sh
backend/build.sh mini/*.sh rhir/all.sh` once.

`make` is the same three steps plus mini, behind the usual targets, on macOS
and Linux:

```
make            frontend, back end, cdc and mini
make test       the regression suite and the mini suite (what CI runs)
make gui        portable GUI checks plus a mac demo image, Darwin only
make rhir       rhir, with its roundtrip suite
make clean      removes every artifact
```

The Makefile drives the same scripts, it does not restate the OCaml module
list or the cargo commands anywhere else. Windows keeps the `.cmd`/`.ps1`
entry points.

`.github/workflows/ci.yml` runs the whole thing on `macos-13`,
`windows-latest` and `ubuntu-latest`. The macOS job is the one that matters
most: it is the only place the Mach-O images this repo writes are executed.

The build host and the target are independent. A Windows host builds macOS
images fine — nothing in `macho.ml` asks the host anything, and `main.ml` picks
the host's format only when `-t` is absent.

## Use

```
rsc examples\hello.rsx
rsc examples\fib.rsx build\fib.exe
rsc -t macos examples\hello.rsx build\hello
```

`./rsc.sh examples/hello.rsx` on the posix side. The `-t` flag has to come
first, before the source path, because the driver scans it before anything else:

```
rsc -t windows examples\hello.rsx build\hello.exe
rsc -t macos   examples\hello.rsx build\hello
```

`rsc.sh` defaults to the host picked from `uname -s` and takes `RSC_TARGET` as
the override, so `RSC_TARGET=macos ./rsc.sh examples/hello.rsx` is the same as
passing `-t macos`. Output names default to the source stem plus `.exe` for
Windows and no extension for macOS.

Or run the stages yourself:

```
rsc.exe examples\fib.rsx -o fib.rsi
rscb.exe fib.rsi -o fib.exe -s examples\fib.rsx
rscb.exe fib.rsi -o fib.macho -s examples\fib.rsx -t macos
```

`rscb` reads the IR, checks it, folds it, emits code, links the image and writes
the executable. `-s` only sets the name that diagnostics use. `-t` selects the
target and defaults to the host. `-v` prints a summary that includes the target
name. The IR file is deleted by the driver after the link.

## Editors

VS Code, Vim 8 and Neovim integrations live in `editors/`. All three are
syntax first and diagnostics second: they read the lines the compilers already
print, `rsc: <file>: line <n>:<col>: <msg>`, `rsc: <file>: line <n>: <msg>` and
`rscb: <file>: <msg>`, and nothing else.

| editor | install |
| --- | --- |
| VS Code | open `editors/vscode/` and press `F5`, or package it into a `.vsix` |
| Vim 8 | `ln -s "$PWD/editors/vim" ~/.vim/pack/rsharp/start/rsharp` |
| Neovim | `{ dir = '.../editors/neovim', ft = { 'rsx', 'mini' } }` |

The repo also ships `.vscode/tasks.json`, so `Ctrl+Shift+B` builds the focused
file with the problem matcher already wired up — no extension required. Vim and
Neovim get `:RsharpBuild` and `:RsharpRun`; Neovim also gets `:RsharpTest` and
`:MiniRun`. Details, including `g:rsharp_rsc` and the `setup()` options, are in
`editors/README.md`.

## The language

### Types

```
i8 i16 i32 i64          signed, two's complement
u8 u16 u32 u64          unsigned
f32 f64                 IEEE 754
bool void
ptr<T>                  raw pointer, unchecked, needs unsafe to touch
&T  &mut T              reference, non-null, checked by the compiler
Box<T>                  owned heap allocation, freed at scope exit
[T; N]                  array of N, N is a literal or an integer const
(T1, T2, ...)           tuple, two or more elements
fn(T1, T2) -> T         function pointer, one word
Task<T>                 handle to a suspended computation, one word
Vec2                    any capitalised name that is a declared struct
T                       a type parameter, only inside the fn that declares it
```

References, boxes, function pointers and tasks are as wide as a pointer and
compile to one. There is no refcount, no GC, no tag, no hidden word.

### Declarations

```
const LIMIT: i32 = 2 + 3 * 4;    compile time, folded, usable as an array size
let x: i32 = 5;                  immutable binding
let y = 5;                       immutable, type taken from the initialiser
var y: i64 = 5;                  mutable binding
var z: f64;                      uninitialised, still mutable
```

The annotation is optional wherever the initialiser can be typed on its own. A
declaration without an initialiser needs one, because there is nothing to infer
from.

A name can be declared again in the same scope. The new binding shadows the old
one from that point on, and the old storage stays alive until its scope ends — a
reference taken before the shadow is still valid, and the two names do not
interfere.

```
let n = 10;
let n = n * 4;      a different binding, typed from its own initialiser
```

`let` means the name is not assignable. It does not make the memory behind a
reference you hold read-only — that is what `&mut` against a `let` refuses to
give you.

Constants are substituted at every use and folded, so `LIMIT * 2` reaches the
encoder as the literal 28. An array size may name a const as long as it is an
integer const declared anywhere in the file.

### References

```
fn bump(c: &mut Counter, by: i32) {
    c.hits += 1;
    c.total += by as i64;
}

fn report(c: &Counter) -> i64 {
    return c.total;
}

bump(&mut c, 10);
report(&c);
```

`&x` borrows shared, `&mut x` borrows exclusive, and `&mut` needs a `var`. A
reference is non-null by construction and lives exactly as long as the checker
can prove its target does. Reading and writing through it is a plain load and
store — the reference erases to a pointer and never costs a branch.

`&[i32; 8]` is a reference to a fixed array, which is how a buffer goes to a
function without decaying into a raw pointer:

```
fn total(buf: &[i32; 8], n: i64) -> i64 {
    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < n) {
        sum += buf[i] as i64;
        i += 1;
    }
    return sum;
}
```

### Boxes

```
let ints: Box<i32> = box(21 * 2);
printf("boxed = %d\n", *ints);

fn make_pair(a: i32, b: i32) -> Box<Pair> {
    return box(Pair { a: a, b: b });
}
```

A `Box<T>` owns its allocation. It is created by `box(expr)`, dereferenced with
`*b` or field access, returned to move ownership, and freed exactly once when
its binding leaves scope. It cannot be copied, reassigned, or passed by value —
the compiler refuses all three, so there is no way to alias one and no way to
free it twice.

Drop glue is emitted at the end of the scope that owns the box, and on `break`,
`continue` and `return` paths that leave it.

### Unsafe

```
unsafe {
    let p: ptr<i32> = &buf[0] as ptr<i32>;
    printf("%d\n", p[1]);
}
```

Four operations require `unsafe` and nothing else does:

- reading or writing through a `ptr<T>`
- indexing a `ptr<T>`
- pointer arithmetic on a `ptr<T>`
- turning a reference into a `ptr<T>`

`ptr<T> as &T` is rejected outright, inside `unsafe` or out of it. A pointer
carries no proof that it is non-null or still points at anything, so there is no
cast that could manufacture that proof.

### Structs

```
struct Vec2 {
    x: f64,
    y: f64
}

let a: Vec2 = Vec2 { x: 1.0, y: 2.0 };
```

A struct literal names every field and the checker says so if one is missing.
Fields are reached with `.`, whether you have the struct, a reference, a box or
a raw pointer to it; the compiler picks the address or the dereference from the
type. `zero(Vec2)` still exists when you want something to fill in later.

A struct field can be an array, an array element can be a struct. Arrays of
arrays and pointers to arrays are not supported.

### Enums

```
enum Color {
    Red,
    Green,
    Blue,
}

enum Shape {
    Circle(i64),
    Rect(i64, i64),
    Nil,
}
```

A variant carries zero or more values and each one has its own type, so `Shape`
is a tagged union. The tag is an `i64` at offset 0 and the payload starts at
offset 8, each field aligned to its own `align_of`. The size is the top of the
layout rounded up to `max(8, widest field alignment)`. A variant is named
`Shape::Circle(4)`, and its index is its position in the declaration.

An enum is an aggregate like a struct or an array: it is passed and returned
through the hidden return pointer, and a `Box` cannot be a payload.

### Tuples

```
let t: (i64, i32, i64) = (10, 20, 30);
let s: (i64, i64) = swap((300, 4));

fn swap(p: (i64, i64)) -> (i64, i64) {
    return (p.1, p.0);
}
```

Fields are reached by position, `.0`, `.1`, and so on. A tuple type needs at
least two elements; a one-element parenthesised expression is just that
expression. Layout follows declaration order with per-element alignment, and the
whole thing is an aggregate — passed by hidden pointer, copied on assignment.

A tuple literal takes its element types from the annotation when there is one.
Without an annotation, a bare integer element is an `i32`.

### Match

```
fn area(s: Shape) -> i64 {
    match s {
        Shape::Circle(r) => {
            return 3 * r * r;
        }
        Shape::Rect(w, h) => {
            return w * h;
        }
        Shape::Nil => {
            return 0;
        }
    }
}
```

The scrutinee is evaluated once into a slot, then dispatched with a compare and
a branch per arm. An arm binds its payload into fresh names inside its own
scope. `_` catches everything left over, which is why it has to be the last arm.
Arms are not expressions; they are blocks, so an arm that means to produce a
value returns or assigns.

### Functions

```
fn dot(a: Vec2, b: Vec2) -> f64 {
    return a.x * b.x + a.y * b.y;
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;
```

`extern` is how a system library gets in. The name is resolved at link time
against the import table the back end writes — a DLL import on Windows, a
`libSystem` symbol on macOS. Extern names are C symbols, so they keep their own
capitalisation — `GetTickCount64` is spelled the way kernel32 exports it, and
`mach_absolute_time` the way libSystem does. Order does not matter, every
function is visible to every other. `main` takes no parameters, returns `i32`,
and is called by a startup stub the back end emits before handing the return
value to `ExitProcess` on Windows or to the `exit` syscall on macOS.

Arrays do not decay on their own. A function that wants a buffer takes a
reference to the whole array, or a raw pointer and you pass `&buf[0] as ptr<i32>`
inside `unsafe`.

### Generics

```
fn max<T>(a: T, b: T) -> T {
    if (a > b) {
        return a;
    }
    return b;
}

fn pick<T, U>(a: T, b: U) -> T {
    return a;
}

max(3, 9)            max$i32
max(1.5, 0.25)       max$f64
pick(41, 1.5)        pick$i32$f64
```

A call site decides the substitution, the compiler writes a concrete function
for it, and the call is rewritten to point at that function. Two sites that agree
share one copy. The template is removed before code generation, so nothing
downstream ever sees a type variable.

There is no box and no table anywhere in that path. `max<i32>` is an ordinary
function with `i32` parameters and an `i32` return: the call is direct, the
arguments are registers, and the branch predictor has nothing to guess. A generic
over an array also knows the width, so the stride is a constant and the elements
are inline:

```
examples/layout.rsx       sizeof(Vec2) = 16, stride(Vec2) = 16, sizeof([Vec2; 4]) = 64
examples/generics.rsx     max i32 = 9, max f64 = 1.500000, min u8 = 41, dot = 13.500000
```

The zero-cost claim is measured, not asserted: a two-site generic `max<T>` over
`i32` and the same program with `max_i32` written out by hand both report `442
bytes of text` from `rscb -v`, with the same instructions in `.text`.

Type parameters are worked out from the argument types at each call. A bare
integer literal is an `i32`, so `max(1 as u64, 2 as u64)` is how you ask for the
`u64` copy. A generic function can be called but not used as a value — there is
no instance to take the address of until a call site picks one, and no vtable
path is generated. Generic bodies are checked once per instantiation, which is
why an error names the copy: `fn add$Vec2: arithmetic on non-numeric type Vec2`.
Structs, enums and tuples can be type arguments; there are no generic structs or
enums of their own.

### Statements

```
let / var           binding
= += -= *= /= %=    assignment to an lvalue
if (cond) { } else if (cond) { } else { }
while (cond) { }
loop { }            bare loop, leave with break
for i in 0..n { }   range loop, half-open; 0..=n includes the last value
break / continue
return expr?;
{ ... }             block, own scope
unsafe { ... }      block, raw pointer access allowed
```

Conditions are parenthesised, same as C.

Every block can also be written without braces and closed with `end;` — the
form reads top to bottom with one terminator per statement, and it nests:

```
fn classify(total: i64) -> i64
    if (total > 100)
        return 1;
    else if (total > 10)
        return 2;
    else
        return 3;
    end;
end;
```

`if`, `else`, `while`, `loop`, `for`, `unsafe` and `fn` all take either form,
and the two mix. In the brace-less form one `end;` closes the whole statement,
`else if` extends the chain instead of nesting inside the arm, and `end` is a
reserved word wherever a block could open. Braced code is unchanged, so both
forms compile to the same tree and the same IR.

### Expressions

```
+ - * / %           arithmetic, ptr<T> + int steps by T
<< >> & | ^ ~       integer ops
== != < <= > >=     comparison, yields bool
&& || !             bool only, short circuit
&x  &mut x          shared / exclusive borrow
*x                  dereference a raw pointer, reference or box
box(e)              heap allocation, owned, freed at scope exit
p[i]  a[i]          pointer or array index
s.f  p.f  r.f  b.f  field, auto deref through pointer, reference or box
f(a, b)             call
e as T              explicit cast, the only conversion there is
sizeof(T)           size in bytes, u64
zero(T)             zero value
null                null pointer
"text"              ptr<u8> to a NUL terminated literal
[1, 2, 3]           array literal, zero filled to the declared length
Vec2 { x: 1.0 }     struct literal
```

Precedence is C's, minus the parts R# does not have.

## What the checker enforces

Types and shapes:

- assigning to a `let` is an error, and so is `&mut` of one
- no implicit numeric conversion: `i32` and `i64` do not mix without `as`
- integer literals adapt to the integer type the context expects, and a bare
  literal next to a typed operand takes that operand's type, so `48 + n` is an
  `i64` sum and `n == 0` compares two `i64`s
- an integer literal must fit the type it lands in: `u8` stops at 255, `u16` at
  65535, `i8` at 127, and `70000 as u16` is a build error instead of the silent
  truncation to 4464 it used to be. An unsigned type also takes the negative
  literals of its own width, read as two's complement, so `-1 as u32` is a mask
- call arity and argument types are checked
- a struct field must exist and a struct literal must name all of them
- arrays cannot be assigned, passed, or returned as values
- `if` and `while` conditions must be `bool`
- return type must match the declaration, `break` needs a loop
- no duplicate names in one scope, no duplicate functions, no duplicate struct
- a generic function cannot be used as a value, and every type parameter must be
  decided by the arguments at the call site
- `main` is required and must be `fn main() -> i32`

Memory safety:

- a shared borrow and an exclusive borrow of the same name cannot be live at once
- a name cannot be assigned while a reference to it is live
- a reference cannot outlive what it points at, and cannot be returned from the
  function whose local it borrows
- `Box<T>` cannot be copied, reassigned, or passed by value
- `ptr<T> as &T` is rejected; a raw pointer never becomes a checked reference
- raw deref, raw index, pointer arithmetic and `&T as ptr<T>` require `unsafe`
- writing through a `&T` is rejected; `&mut` is the only way to write through a
  reference
- a local scalar must be assigned before it is read

The checker reports every error it finds in one run, not just the first:

```
rscb: examples/x.rsx: fn main: 'locked' is immutable; declare it with 'var' to assign to it
rscb: examples/x.rsx: fn main: 'f' takes 1 argument(s), got 2
rscb: examples/x.rsx: fn main: P { ... } is missing field 'y'
rscb: examples/x.rsx: fn main: 'x' is already borrowed; an '&mut' needs exclusive access
rscb: examples/x.rsx: fn bad: returning a reference to a local; the local is gone before the caller looks
rscb: examples/x.rsx: fn main: a raw pointer cannot become a reference; nothing proves it is valid
```

The borrow pass is a statement-level analysis, not a full lifetime solver. It is
conservative: a borrow is live for the duration of the statement that creates
it, plus the scope of the binding that holds it. That rejects a few programs
that would be fine in principle, and it never accepts one that is not.

## What safety costs

Measured on `examples/bench.rsx`: 256 million inner iterations over a checked
array, then the same loop over a raw pointer inside `unsafe`.

```
safe   1547 1594 1578 ms
raw    1500 1531 1500 ms
```

That is what a surviving check costs — a compare and a branch, 3–6% on a loop
that does nothing but index. In the tree as it stands no check survives in the
examples: `range.ml` proves every index in range, and `arrays.exe`, `safety.exe`,
`bench.exe`, `layout.exe` and `generics.exe` all count zero `ud2` in the image.
What is left is the index the proof cannot reach:

```
fn at(i: i64) -> i32 {
    var xs: [i32; 6] = [1, 2, 3, 4, 5, 6];
    return xs[i];
}

let f: fn(i64) -> i32 = at;
f(99);              one check survives, and the process traps
```

Called through a function pointer — a call the inliner leaves alone — `at` keeps
its one check, and `f(99)` exits `-1073741795` (`STATUS_ILLEGAL_INSTRUCTION`)
instead of reading past the array.

The proof is an interval analysis over each function. A constant `for` range
bounds the index; so does a dominating `if (i < n)` in both polarities, a binding
or assignment that carries a known interval, and a `const` value. The interval is
dropped when the name is assigned, shadowed, has its address taken with `&`, or
when two branches merge with different answers; arithmetic that might overflow
abandons it too, because a wrapped number is not the one the bound was proved
for. A constant index still folds at emission, which is now the simplest case of
the same proof.

The rest of the safety model costs nothing at all. References, `&mut`, and box
dereferences compile to the same instructions a raw pointer would. Drop glue is
one call to `free` at scope exit, with no reference count and no deferred queue.

## What it does not have

No generic structs or enums, no traits or bounds, no generic function taken as a
value, no capturing closures, no modules, no strings as values, no standard
library, no operator overloading, no comptime execution beyond const folding, no
arrays of arrays, no wide pointers (a reference is one word, so a slice is not a
value).

There is no CRT. A program that wants libc calls declares it and the call goes
through the import table. On Windows that is `msvcrt.dll` or `kernel32.dll`;
`printf`, `puts`, `putchar`, `malloc`, `free`, `calloc`, `realloc`, `memcpy`,
`memset`, `sprintf`, `ExitProcess`, `Sleep`, `GetTickCount64`, `GetStdHandle` and
`WriteFile` are the names the back end routes.

On macOS every libc name goes to `/usr/lib/libSystem.B.dylib`, plus
`mach_absolute_time` for timing. The four Windows-only names — `ExitProcess`,
`Sleep`, `GetTickCount64`, `GetStdHandle`, `WriteFile` — are a build error
against `-t macos` that says which name was wrong, instead of an image that
loads and then fails to bind. `snprintf` is not in the table; msvcrt spells it
`_snprintf` and the import name has to match the export exactly.

## Inside the split

The Rust half never decides anything semantic. It produces text:

```
(program
  (const limit i32 (bin + (int 2) (int 3)))
  (fn main
    (ret i32)
    (body
      (let x (array i32 4) (arraylit (int 1) (int 2)))
      (expr (call puts (str "hello")))
      (return (int 0))
    )
  )
)
```

The OCaml half runs the program through these, in order: parse into a tree with
the array sizes resolved; monomorphise every generic function into the copies its
call sites asked for; fill in a type for every expression in place while
collecting errors; check borrows and definite assignment; fold constants and drop
branches that can no longer be reached; inline calls and remove functions `main`
cannot reach; fold again, because inlining exposes new constants; prove array
indices in range; then emit code.

A generic function carries its type parameters on the definition, and every place
a parameter appears is written `(var T)`:

```
(program
  (fn max
    (generic T)
    (param a (var T))
    (param b (var T))
    (ret (var T))
    (body ...)
  )
)
```

That is the whole extension to the IR: a definition may name type parameters and
use them in types. Everything after `mono.ml` sees only concrete types.

### Monomorphisation

`typeck.ml` types the arguments at a call, matches them against the parameter
types, and rewrites the call in place to a mangled name — `max$i32`,
`pick$i32$f64` — parking the request for `mono.ml`. The driver is a fixpoint: it
typechecks the program to discover requests, builds the fresh copies, and repeats
until a round asks for nothing new, because a copy can itself call a template.
Templates are removed at the end, and `cg.ml` fails loudly if a type variable
survives.

Copies are laid out where their template stood, in the order the call sites were
seen, so a generic program and its hand-written equivalent produce the same
function order and the same addresses. Two call sites that agree on the
substitution share one copy. Nothing about the call changes shape: after this
pass it is a direct call to a name with no type variable in it.

### Inlining and dead functions

`lto.ml` runs over the whole program after the first fold:

- a call to a function with a single `return` at the end, no more than 20
  statements, no `break` or `continue` leaving it, and no `Box` in its signature
  is spliced into the caller. The return value goes through a fresh temporary
  declared outside the spliced block, so a local in the callee cannot capture the
  write. Four rounds, 4000 sites per round. A pure single-expression body is also
  inlined as an expression when every argument is a variable or a literal.
- starting at `main`, every function not reached through a call, a function
  reference or a bare name is removed.

`-v` reports both passes and the image that results:

```
rscb: mono: 8 copy(s) of 6 generic fn(s)
rscb: lto: 3 site(s) inlined, 3 of 9 fn(s) unreachable
rscb: windows-x86_64: 0 const(s), 1 struct(s), 1 extern(s), 6 fn(s) -> 2130 bytes of text, 4096 bytes of image
```

on `examples/generics.rsx`.

### Code generation

Target is x86-64. The register assignment comes from `target.ml`, the frame and
the spill logic ask it, and everything below the argument marshalling is shared
between the two ABIs.

Windows, Microsoft calling convention: integer and pointer arguments go in
`RCX RDX R8 R9`, float arguments in `XMM0`–`XMM3`, positional — the fifth and
later arguments go on the stack at `[rsp+32]` and up, behind 32 bytes of shadow
space. A struct argument is passed as a pointer to a copy and the callee copies
it into its own frame, so mutation inside a function does not reach the caller.
A struct return uses a hidden pointer in `RCX`, which shifts the register
positions of everything else by one.

macOS, System V: integer and pointer arguments go in `RDI RSI RDX RCX R8 R9`,
float arguments in `XMM0`–`XMM7`, and the two files have independent counters —
an all-float call fills `XMM0`–`XMM7` and never touches the integer registers,
where Win64 would have run out at four. The seventh integer and ninth float go
on the stack at `[rsp]` and up with no shadow space; the callee reads them at
`[rbp+16]`. A struct return uses `RDI`, which consumes an integer slot, so the
first real argument starts at `RSI`. `AL` carries the number of vector registers
used, which is what a variadic callee reads, and it is set to the float count
before a call to `printf`.

Every function is laid out the same way: `push rbp; mov rbp, rsp; sub rsp, N`,
where `N` is patched once the body has been generated and the deepest temporary
is known. Locals and temporaries grow downward from `rbp`; on Windows the shadow
space sits at the bottom of the frame and on macOS it does not exist. `rsp` does
not move inside a function except around calls, and every call site leaves
`rsp` 16-byte aligned. Functions are padded to 16 bytes with `nop`.

A frame larger than one page is probed before it is used — the prologue walks
down from `rbp` in 4 KiB steps touching each page, the same thing `__chkstk`
does, because Windows grows a stack one guard page at a time and a 160 KiB frame
that lands on its first byte would otherwise fault 39 pages past the guard.
Frames of a page or less skip the probe with a jump patched to fall straight
through. The probe is harmless on macOS, where the stack is committed up front
and the walk just touches pages that are already there.

Copies of 64 bytes or less are unrolled into `mov` pairs; larger ones use
`rep movsb`. A bounds check is `mov rcx, n; cmp rax, rcx; jb ok; ud2; ok:`, and it
is emitted only where `range.ml` could not prove the index in range: a constant,
a `for` bound, or a dominating comparison all remove it. Imports are collected
from the calls that were actually emitted and deduplicated by name.

A value that has to survive drop glue on its way out of a `return` is staged in
a stack temporary first. Integers come back in `RAX` and floats in `XMM0`;
without the staging the `free` for a `Box` still live in the scope would clobber
`XMM0` and hand the caller a freed pointer value as a float.

Strings land in `.rdata` on Windows, `__cstring` on macOS, and are addressed
RIP-relative in both. The list of relocations is collected during emission and
patched after the module is complete, when every label offset is final.

### The Windows image

`pe.ml` writes the file from scratch. DOS header, `PE\0\0`, PE32+ optional
header, three section headers, an import directory with one descriptor per DLL.
`SectionAlignment` and `FileAlignment` are both `0x200`, so an RVA is its own
file offset and the writer never has to translate between the two. Image base
is `0x140000000`. The image is marked `RELOCS_STRIPPED | EXECUTABLE_IMAGE |
LARGE_ADDRESS_AWARE`, which is legal because nothing in the image is absolute:
internal calls are `rel32`, imports resolve through the IAT, and data references
are RIP-relative.

Sections are `.text`, `.rdata`, `.idata`. The import table is built at the end:
descriptors, then the import lookup tables, then the IAT, then DLL name strings,
then hint/name entries deduplicated by name.

## The macOS target

`macho.ml` writes a 64-bit x86 Mach-O with the same "nothing absolute" rule.
Four segments, laid out in file order and mapped 1:1, so a virtual address is
`0x100000000 + file offset` and the writer never translates either:

```
__PAGEZERO   0x100000000 bytes of no-access guard at address 0
__TEXT       __text     code, at file offset 0, pure instructions + some data
             __cstring  the string literals
__DATA       __got      one 8-byte slot per imported symbol
__LINKEDIT   bind stream, symbol table, string table, indirect symbol table
```

Eleven load commands: the four segment commands, `LC_LOAD_DYLINKER`
(`/usr/lib/dyld`), `LC_LOAD_DYLIB` (`/usr/lib/libSystem.B.dylib`),
`LC_DYLD_INFO_ONLY`, `LC_SYMTAB`, `LC_DYSYMTAB`, `LC_MAIN`, and
`LC_BUILD_VERSION` pinned at macOS 11.0. The `__text` section is flagged
`S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS`, `__got` is
`S_NON_LAZY_SYMBOL_POINTERS`, and the indirect symbol table points slot `i` at
undefined symbol `i`.

No rebase opcodes are emitted at all, because no pointer in the image needs
one: calls are `rel32`, string references are RIP-relative, and imports go
through the GOT. Imports are bound with classic dyld bind opcodes in
`LC_DYLD_INFO_ONLY` rather than chained fixups — `bind` into segment 2, then for
each symbol `set_dylib_ordinal_imm 1`, `set_symbol_trailing_flags_imm`, name,
`do_bind`, `done`. x86-64 dyld still accepts that form, and it is legible in a
hex dump in a way a chained fixup chain is not.

Every `FF 15` call site is patched to `[rip + disp32]` landing on its slot in
`__got`, and every symbol in `LC_SYMTAB` is `N_UNDF | N_EXT` with value 0 and an
underscore prefix, so dyld resolves it against libSystem. Symbols are
deduplicated and the `__got` size is exactly `8 * nsym`.

Entry is `LC_MAIN` with `entryoff = text_off + entry`. The stub:

```
and rsp, -16
call main
mov edi, eax
mov eax, 0x2000001
syscall
hlt
```

`0x2000001` is `exit` on Darwin (class 2, syscall 1). No `ExitProcess`, no
libSystem startup, no `_start`; the kernel enters at the offset `LC_MAIN` names
and the process is done the moment `main` returns.

`rscb` marks the image executable as it writes it, so `./hello` runs with no
`chmod` step. A Mach-O with no signature runs on x86-64 macOS from a terminal,
and on Apple Silicon under Rosetta. There is no arm64 target yet: the encoder is
x86-64, so an arm64 back end would be a second `x64.ml`, not a flag.

This path is no longer structural-only. `.github/workflows/ci.yml` builds and
runs the suite on `macos-13`, an Intel runner, so every example in `regress.sh`
compiles to a Mach-O and executes there. Before that job existed, every
`.macho` was only checked structurally (segment and section congruence, load
command sizes, symbol types, bind stream decoding, call sites landing on GOT
slots) and by disassembling `__text`.

`examples/bench_mac.rsx` is the macOS timing loop, using `mach_absolute_time`
instead of `GetTickCount64`, because the Windows import is a build error against
this target. Both regression drivers build it with `-t macos` on every host —
`regress.cmd` reports it as a built image, `regress.sh` runs it on macOS.

## rhir — the second toolchain

`rhir/` is a compiler in Rust that shares no code with the OCaml back end. It
reads a textual SSA IR, optimises it, selects x86-64, allocates registers,
encodes instructions and writes a PE32+ image. Same rule as the rest of the
repository: no gcc, no assembler, no linker, no CRT, and no crates either — the
standard library is all it uses.

```
   .rhir  --[rhirc]-->  .exe
   SSA text             PE32+ image, Win64
```

It exists because the R# back end emits from an AST. Optimisation wants a form
where every value has one definition and every block has explicit edges and
predecessors; `rhir` is that form written down, with everything downstream of
it.

### Use

```
rhirc tests\fib.rhir -o fib.exe
rhirc tests\fib.rhir --emit-ir
```

`--emit-ir` runs the same pipeline and prints the module back out in the input
grammar. The output parses: feeding it to `rhirc` again produces an image that
exits with the same code. `all.cmd` checks exactly that — it compiles every
`tests\*.rhir`, runs it, re-assembles the emitted IR, runs that, and fails if the
two exit codes differ.

### The IR

```
declare i64 @GetStdHandle(i64)
declare i64 @WriteFile(i64, ptr, i64, ptr, ptr)

global @msg = "hello rhir\n"

func @main() -> i64 {
entry:
  %0 = alloca i64, 1
  store i64 0, ptr %0
  br loop
loop:
  %1 = phi i64 [ 0, entry ], [ %2, loop ]
  %2 = add i64 %1, 1
  %3 = icmp slt i64 %2, 10
  condbr %3, loop, done
done:
  ret i64 %1
}
```

Types are `i1 i8 i16 i32 i64 ptr`, and every value carries one. A block label is
an identifier, a value is `%` and a number, a symbol is `@` and a name. Value
numbers need not be dense and need not be in order — the parser rejects a value
defined twice and a value used before it is defined, and nothing else.

```
%x = alloca T, n              frame space for n elements of T; %x is a ptr
%x = load T, ptr %p           load of T
store T %v, ptr %p
%x = gep T, ptr %p, i64 %i    p + i * sizeof(T)
%x = add|sub|mul i64 %a, %b
%x = sdiv|udiv i64 %a, %b
%x = and|or|xor i64 %a, %b
%x = shl|sar|shr i64 %a, %b
%x = icmp eq|ne|slt|sle|sgt|sge|ult|ule|ugt|uge T %a, %b
%x = trunc|zext|sext T %v to U
%x = select i64 %c, i64 %a, i64 %b
%x = phi i64 [ %a, entry ], [ %b, loop ]
%x = call i64 @f(i64 %a, ptr %b)
ret i64 %v / ret
br block
condbr %c, then, else
```

A constant can stand where a value can: `add i64 %a, 1`, `store i8 48, ptr %p`.
A global can stand where a pointer can: `ptr @msg`. `phi` needs one entry per
predecessor and the incoming blocks must actually be predecessors.

### The pipeline

```
parse -> simplify_cfg -> mem2reg -> constfold -> dce -> ... -> isel
```

- `simplify_cfg` threads jumps, folds a `condbr` whose condition is a constant,
  and drops blocks that nothing reaches.
- `mem2reg` promotes `alloca` slots to SSA values. Escape analysis marks an
  alloca as un-promotable when its address reaches a store, a call or a gep, so
  an array that is only ever indexed stays in memory while a scalar counter
  becomes a phi. Promotion is Cytron's: dominance frontiers, then phis, then
  renaming down the dominator tree. It is the pass that turns the `promote` test
  from six instructions of load/store into one phi.
- `constfold` evaluates any instruction whose operands are all constants,
  including casts and comparisons, and folds `select` with a constant condition.
  Results are normalised to the width of their type, so `add i32 2000000000,
  2000000000` is `-294967296` and the upper 32 bits of the register are that
  value sign-extended, not the 40-bit sum.
- `dce` drops instructions whose result is never used, iterating to a fixpoint
  so a chain of dead arithmetic disappears entirely.

The four passes run in a loop until nothing changes, capped at 32 rounds.

### Code generation

Lowering produces a MIR with virtual registers keyed by IR value id, so no
renumbering is needed anywhere. Register allocation is a linear scan over
`RBX RSI RDI R12 R13 R14 R15`; a value that does not fit goes to a frame slot and
the encoder loads it into `RAX`, `R10` or `R11` on use. Live ranges come from
real block liveness — uses and defs per block, then a fixpoint over successors —
because a scan over plain instruction positions never sees that a value is live
across a back edge and hands the same register to two values in a loop.

A phi becomes a frame slot: each predecessor edge stores its incoming value into
the slot and the phi loads it at the top of its block. An edge that needs to do
that and has no block of its own is split.

Win64: the first four arguments are `RCX RDX R8 R9`, the rest go on the stack at
`[rsp+32+8*(i-4)]` with `8*outgoing` bytes reserved in the frame, and the callee
reads them at `[rbp+48+8*(p-4)]`. Integers and pointers only. A call to an
import is `mov rax, imm64(&IAT slot)` followed by `call qword ptr [rax]` — the
slot holds the resolved address, so the call dereferences it rather than jumping
to the slot itself. Returns come back in `RAX`.

Every `i32` operation is followed by a sign-extending move of the low 32 bits, so
32-bit arithmetic wraps at 32 bits and a `sext` later reads the right sign.

### The image

`pe.rs` follows the same plan as `pe.ml` with a different layout: one `.text` at
RVA `0x1000`, one `.rdata` after it, `0x400` of headers, 512-byte file
alignment, image base `0x140000000`, relocations stripped. `.rdata` is marked
writable because the loader writes resolved addresses into the IAT, which sits in
it, and because the import directory does too.

Only `KERNEL32.dll` is imported. The entry stub is

```
sub rsp, 40
call main
mov rcx, rax
mov rax, &ExitProcess
call qword ptr [rax]
```

so a module with no `main` fails at link time with the name in the message.

### Tests

`all.cmd` builds and runs each of these, then rebuilds it from its own emitted
IR and compares exit codes:

```
array      285          sum of squares 0..9 through alloca + gep + load
casts      116          sdiv/udiv, trunc, zext, sext on mixed widths
fib        6765         recursive, two calls per frame
hello      prints       GetStdHandle + WriteFile on a global string
i32        0            32-bit overflow, then sext to 64
itoa       prints       division loop writing digits backwards into a global
loop       45           phi loop, two carried values
promote    100          alloca counter promoted to a phi
ret        7            smallest module that can exist
spill      78           twelve live values, forced frame slots
stackargs  21           six parameters, two of them on the stack
strlen     38           byte-at-a-time scan of a global, result as exit code
```

### What it does not have

No floating point, no structs, no aggregates, no first-class arrays — an array is
an `alloca` and a `gep`. Globals are byte strings and nothing else. One external
DLL, eight arguments, 64-bit slots, no variadic definitions (only calls to
variadic imports). There is no macOS or ELF counterpart: the Mach-O writer lives
in the OCaml back end and `rhir` has no equivalent.

## Mini — a compiler written in R#

`mini/` is a compiler for a small language, and the compiler itself is an R#
program. The portable core never touches the OS: it calls only the `host_*`
layer — `host_win.rsx` on Windows, `host_mac.rsx` on macOS — and the build
concatenates one host onto the core. No macros, no conditional compilation, one
translation unit per platform.

```
prog.mini --[mini.exe]--> prog.rsi --[rscb, the R# back end]--> prog.exe
```

`mini -v` prints the banner; `mini < prog.mini` with no arguments reads Mini
on stdin and writes IR on stdout. The three flags:

- `mini --emit file.mini [-o out.rsi]` — IR to stdout, or to a file
- `mini --aot file.mini [-o out]` — compile, write the IR to a temp file, run
  the back end found at `<the mini binary's directory>/../backend/rscb.exe`,
  delete the temp file. Without `-o`, the output is the source name with the
  host extension swapped in
- `mini --jit file.mini [args]` — like `--aot`, but into a temporary image,
  run it with the remaining arguments, delete the image, exit with the
  program's exit code. It is AOT either way; the temp image is just an
  artifact on the road to running it

```
mini\run.cmd mini\examples\fib.mini     :: builds the compiler, then fib.exe
mini\test.cmd                           :: AOT, JIT, the stdin filter and the banner
```

`run.cmd` rebuilds the compiler from source every time, so editing
`src/mini.rsx` is all it takes to change the language. On the posix side
`run.sh` and `test.sh` do the same; `test.sh` passes paths through `cygpath
-w` when it exists, because mini spawns the back end itself and never gets to
see MSYS path translation. Both drivers check AOT output, JIT output, the
stdin filter's link step and the banner, comparing bytes where there is a
file to compare.

Mini is i64-only: functions, `let`/`var`, `if`/`else`, `while`, `break`,
`continue`, `case` with comma-listed values and an optional `else` arm,
`print`, `abs`, `min`, `max`, `puts`, `putc`, `len` of a string literal,
`&&`, `||`, `!`, compound assignment, string literals and `//` comments. One
type means no inference, which is what keeps the whole thing in one portable
file. Diagnostics carry a line number, the source line, and a caret.

The interesting part is the shape: one token of lookahead over the source
buffer (no token array), expressions as a 65,536-node index pool rewound at
the start of every statement, IR emitted straight into a 32 MB flat buffer.
There is no AST on disk and no allocator in the compiler — a 1 MB source
buffer, a 3.5 MB node pool and the output buffer are grabbed once at startup
and that is all the memory it uses.

See `mini/README.md` for the grammar, the host split, the limits and the
measurements.

## CDC

`cdc/` is the package manager. Rust, no dependencies, one binary. The shape is
npm's — manifest, lockfile, `add`, `remove`, `install`, `publish`, `search`,
`tree` — and the semantics are cut down to what this language can actually
honour.

The one deliberate difference: CDC never speaks HTTP. The registry is a
directory tree on disk. A network registry would mean TLS, auth, a server, and a
mirror policy bolted onto a compiler that fits in fifteen OCaml modules, and none
of that would make a package resolve any differently. A directory you can
`dir` is a registry you can inspect, back up, put on a share, or carry on a USB
stick.

```
$CDC_REGISTRY/            default: ~/.cdc-registry
  mathx/
    0.1.0/
      cdc.json
      src/lib.rsx
    0.2.0/
      cdc.json
      src/lib.rsx
```

`CDC_REGISTRY` overrides the location and is created on first use.
`cdc publish` copies the project into it — minus `cdc_modules`, `build`,
`target` and `.git` — and refuses to overwrite a published version unless you
pass `--force`.

### cdc.json

```json
{
  "name": "app",
  "version": "0.1.0",
  "description": "demo",
  "main": "src/main.rsx",
  "dependencies": {
    "mathx": "^0.1.0",
    "textx": ">=0.1.0 <0.3.0"
  }
}
```

`name` is lowercase letters, digits, `.`, `-`, `_`, and has to start with a
letter or digit. `version` is exactly `major.minor.patch`; pre-release and build
tags are rejected rather than half-supported. `main` is the entry source for an
app, `lib` for a library, both relative paths inside the package. With neither,
`src/main.rsx` then `src/lib.rsx` are used in that order. Dependencies are a map
of name to range.

### cdc.lock

```json
{
  "lock_version": 1,
  "packages": [
    { "name": "mathx", "version": "0.1.0",
      "hash": "e28d6ff33309fdcd559de27722bbb4f82b31244de735e70806df9e826314d6da" }
  ]
}
```

The hash is SHA-256 over a canonical walk of the package tree: relative paths
sorted, then for each file the path, a NUL, the length as little-endian u64, and
the bytes. `cdc install` reuses a `cdc_modules/<name>` directory whose hash
matches and rewrites it otherwise, so an unchanged lock re-installs as
`2 packages, 2 reused` and touches nothing.

The lock also feeds the resolver as preferred versions. A version already in the
lock wins over a newer one that still fits the range, so `cdc install` does not
drift forward when something is published. To move, add a range that excludes
the locked version, or delete `cdc.lock` and let the newest fitting version win.

### Commands

```
cdc new <name> [--lib]        scaffold an app or library in ./<name>
cdc init [--name <name>]      scaffold into the current directory
cdc install                   resolve, fetch into cdc_modules/, write cdc.lock
cdc add <name>[@<range>]      add a dependency, then install
cdc remove <name>             drop a dependency, then install
cdc build [-t <target>] [-o <file>]
cdc run [-t <target>] [-- args...]
cdc publish [--force]         copy this package into the registry
cdc search [term]             list registry packages, name and description
cdc tree                      print the resolved graph
```

`cdc add` without a range picks the newest published version and writes a
caret range. If resolution fails, `cdc.json` is left exactly as it was — the new
dependency is validated against the whole graph before anything is written.

### Ranges

The subset is `1.2.3`, `=`, `>`, `>=`, `<`, `<=`, `^`, `~`, `*`, and bare
x-ranges (`1`, `1.2`). Comparisons joined by whitespace are ANDed. There is no
`||`, no hyphen range, and no pre-release ordering, because versions cannot have
pre-release tags. The comparison operators want a full three-part version;
partial versions are only meaningful bare or behind `^` and `~`.

Caret follows the usual rule with the 0.x exceptions: `^1.2.3` is `>=1.2.3
<2.0.0`, `^0.2.3` is `>=0.2.3 <0.3.0`, `^0.0.3` is `>=0.0.3 <0.0.4`, and a
partial caret widens to the next unspecified field. Tilde pins the minor:
`~1.2.3` is `>=1.2.3 <1.3.0`.

### Resolution

One version per name for the entire graph. Not "one per dependent" — one, full
stop. Candidates are the published versions that satisfy every range asking for
that name, tried newest first with the lockfile's pick hoisted to the front, and
the solver backtracks when a choice makes some later package unsatisfiable.

When two packages genuinely disagree, the error names both:

```
cdc: mathx 0.1.0 is already selected, but texty 0.1.0 needs mathx 0.2.0
```

npm would install both copies and let each dependent see its own. CDC can't,
and the reason is in the compiler: R# has no module system and no symbol
mangling. Packages are merged by pasting source into one translation unit, so
two copies of `mathx` are two definitions of `mathx_add` and the build dies at
the second one. Forking versions would need namespaces, and namespaces are a
language feature this language does not have yet. Erroring at resolve time is
the honest version of that constraint; mangling every exported name would have
made the link succeed and the code twice as large.

### Building a package graph

`cdc build` installs, walks the dependency graph depth-first, deduplicates, and
concatenates the sources in post-order with the root package last:

```
cdc_modules/mathx/src/lib.rsx        no dependencies of its own
cdc_modules/textx/src/lib.rsx        calls mathx
src/main.rsx                         calls both
```

That file is written to `build/<name>.rsx` and handed to `rsc -t <target>` as a
single translation unit, so a call across packages is an ordinary call and the
folder and the borrow checker see the same program they would if you had written
it by hand in one file. Output goes to `build/`, or wherever `-o` points.

Before compiling, CDC scans every source for top-level `fn`, `struct`, and
`const` declarations and reports duplicates with both locations and both package
names:

```
cdc: 'mathx_add' is defined twice:
  ...\cdc_modules\mathx\src/lib.rsx:1 (mathx)
  ...\src\main.rsx:3 (app)
```

Repeated `extern` declarations of the same name are fine and are treated as one
— a library and the app both declaring `printf` is normal, not a conflict.

### Locating the compiler

`CDC_RSC` wins if set. Otherwise CDC walks up from its own executable and from
the working directory looking for `rsc.cmd` or `rsc.sh`, which is what makes
`cdc\target\release\cdc.exe` work from anywhere inside the repository. `.cmd`
and `.bat` drivers are spawned through `cmd /c`. The target defaults to the
host; `cdc build -t macos` writes a Mach-O with no extension, and the same
`-t` reaches `rsc`.

### What CDC is not

- No HTTP registry, no auth, no mirroring, no CDN. A registry is a directory.
- No prebuilt artifacts. A package is source; it is compiled with the app that
  uses it. There is no ABI to keep stable because there is no binary boundary.
- No second copy of a package in one graph, as above.
- No install scripts. Nothing in a package runs at install time. The only thing
  CDC executes is `rsc` and, for `cdc run`, the program it just built.
- No workspaces, no patches, no overrides, no `node_modules`-style nested tree.
- No signatures. The lockfile hash detects drift between installs; it does not
  authenticate the registry.

## The HTTP stack

`modules/http/` is a working HTTP client written in plain R#: HTTP/1.1, HTTP/2,
HTTP/3 over QUIC, TLS 1.3, HPACK and QPACK, and X.509 chain validation against
the Windows root store or against a caller-supplied anchor. Nothing in it needs
compiler support, an external library or a build step — a program includes the
files it wants and the whole stack compiles into one image.

```rsx
include "modules/http/http_request.rsx";

fn main() -> i32 {
    var r: HResp = hresp_new();
    let rc: i32 = http_get("https://example.com/", &mut r);
    if (rc != HR_OK) {
        printf("fetch failed: %d\n", rc);
        return 1;
    }
    printf("%lld %lld bytes\n", hresp_status(&mut r), hresp_body_len(&mut r));
    hresp_free(&mut r);
    return 0;
}
```

### Files

Portable code — no OS calls beyond libc:

```
rt.rsx              byte buffers, libc externs, hex, time
sha1.rsx            SHA-1, used only by TLS key derivation for older peers
sha256.rsx          SHA-256
sha512.rsx          SHA-512 and SHA-384
hmac.rsx            HMAC-SHA256, HKDF
aes_gcm.rsx         AES-128-GCM, AES-NI free
bignum.rsx          big integers, modular exponentiation
rsa.rsx             RSA PKCS#1 v1.5 and PSS verification
ec.rsx              P-256 and P-384 field/point arithmetic, ECDSA verify
x25519.rsx          X25519
der.rsx             DER reader
x509.rsx            certificate parse, SAN/CN matching, validity, chain verify
tls13.rsx           TLS 1.3 client handshake and record layer
http1.rsx           request builder, status line and header parser, chunked decode
http1_client.rsx    HTTP/1.1 connection over any byte stream with ALPN
hpack_tables.rsx    RFC 7541 static table and Huffman tables
hpack.rsx           HPACK encoder and decoder
http2.rsx           HTTP/2 frame codec
http2_client.rsx    HTTP/2 connection, one request at a time
quic_crypto.rsx     QUIC varints, packet protection, header protection
quic_conn.rsx       QUIC connection state, CRYPTO reassembly, flow control
quic_frame.rsx      QUIC frame codec
quic_tls.rsx        TLS 1.3 handshake carried over QUIC CRYPTO streams
quic_client.rsx     QUIC client
qpack_tables.rsx    RFC 9204 static table, 99 entries
qpack.rsx           QPACK codec, static table only
h3_client.rsx       HTTP/3 driver: control streams, request streams, QPACK
http_request.rsx    URL parsing, request and response objects, transport choice
```

Windows transports, kept apart because R# has no conditional compilation:

```
transport_win.rsx   WinSock, DNS, TCP, UDP, HTTP CONNECT, timeouts
https_win.rsx       TLS over TCP, ALPN offer, OS trust, plain TCP mode
roots_win.rsx       294 trust anchors read out of the Windows store
trust.rsx           store walk and chain verification
quic_win.rsx        QUIC plus OS trust
h3_win.rsx          HTTP/3 plus OS trust
```

### Trust

`http_get`, `hreq_fetch`, `h3_open_os` and `https_open` verify the chain against
the machine's root store. Each layer also takes an anchor directly —
`http_get_anchor`, `hreq_fetch_anchor`, `h3_open` plus `h3_trust_anchor`,
`https_open_anchor` — which is what the local CA in `work/http/certs` uses.
Host matching is CN and SAN, case-insensitive, with single-label wildcard
support; validity is checked against `rt_time()`. There is no insecure mode: a
failed chain returns `HR_TLS` and no request bytes leave the process.

### Requests

`HReq` owns the method, URL, header list and body; `HResp` owns the status, the
decoded header list and the body.

```rsx
var q: HReq = hreq_new();
hreq_open(&mut q, "POST", "https://example.com/upload?x=1");
hreq_set_version(&mut q, HTTP_V2);
hreq_header(&mut q, "content-type", "application/json");
hreq_body(&mut q, payload, plen);

var r: HResp = hresp_new();
let rc: i32 = hreq_fetch(&mut q, &mut r);
```

- `hreq_open` parses `http://` and `https://`, default ports, bracketed IPv6
  hosts, query strings and fragments. A scheme it does not know returns
  `HR_URL`, a bad port returns `HR_URL`, and nothing is dialled.
- `hreq_header` rejects names with spaces or colons and values with CR or LF.
  `host` and `content-length` are written by the transport, and HTTP/2 and
  HTTP/3 drop hop-by-hop headers as well.
- `hreq_set_version` picks `HTTP_V11`, `HTTP_V2` or `HTTP_V3`. HTTP/2 and HTTP/3
  require `https://`; plain `http://` is HTTP/1.1 only.
- `hreq_body` takes a pointer and a length; `q.max` bounds it, `q.to_ms` bounds
  the whole exchange.
- `hreq_fetch` verifies against the machine's root store;
  `hreq_fetch_anchor` takes a DER anchor instead, which is how a private CA is
  trusted.
- `hresp_status`, `hresp_body`, `hresp_body_len`, `hresp_body_str`,
  `hresp_header`, `hresp_header_len`, `hresp_header_copy`, `hresp_header_at`
  and `hresp_header_count` read the response. Header lookup is
  case-insensitive.

The wrappers `http_get`, `http_post`, `http_send` and their `_anchor` variants
build the object for one call.

### Verification

`work\http\run.cmd` builds and runs the whole suite. The vector tests are
offline: digests, HMAC, AES-GCM, bignum, DER, EC, RSA, X25519, X.509, the root
store, HPACK, QPACK, HTTP/2 frames, QUIC packets and frames, and the TLS/QUIC
handshake transcripts. Their expected bytes come from the RFCs and from
`aioquic`, `h2`, `hpack` and `pylsqpack`, so agreement is agreement with an
independent implementation and not with this code.

The live tests dial Python fixtures on loopback: `server.py` (8099) for plain
HTTP, `https_server.py` (4433 RSA, 4434 ECDSA), `http2_server.py` (4443, 4444),
`proxy_server.py` (8888) and `h3_server.py` (4445, aioquic). The script starts
them, runs `t_transport`, `t_tls`, `t_https`, `t_h2`, `t_request`, `t_quiclive`
and `t_h3`, then stops them through the pid files. A run ends with
`http suite: ok`. `run.cmd up` and `run.cmd down` start and stop only the
fixtures, which is how a single test is driven by hand. The test CA ships as
public certificates only; the keys are generated locally and are not committed,
so on a fresh clone the `gen_*.py` scripts in that folder regenerate them
before the suite passes.

### Scope

- TLS 1.3 only, `TLS_AES_128_GCM_SHA256` only, X25519 only, RSA-PSS, PKCS#1 and
  ECDSA P-256/P-384 certificate signatures. No TLS 1.2, no resumption, no
  HelloRetryRequest, no 0-RTT, no client certificates.
- ALPN is offered as `h2` plus `http/1.1` by default; the HTTP/1.1 client offers
  `http/1.1` alone and the HTTP/2 client `h2` alone.
- HTTP/1.1 handles `Content-Length`, chunked and close-delimited bodies, 1xx
  interim responses and keep-alive. One request at a time.
- HTTP/2 handles one stream at a time, HPACK with the static and dynamic table,
  SETTINGS, PING, WINDOW_UPDATE, GOAWAY, RST_STREAM and CONTINUATION. No server
  push, no prioritisation.
- QPACK is static-table only: the client advertises
  `SETTINGS_QPACK_MAX_TABLE_CAPACITY = 0` and `BLOCKED_STREAMS = 0`, and the
  decoder rejects dynamic-table and post-base forms.
- An HTTP/3 request body is capped at 900 bytes (`H3_CHUNK`); response bodies
  are capped by `q.max`, 8 MiB by default.
- HTTP/1.1 and HTTP/2 can go through an HTTP CONNECT proxy. HTTP/3 cannot.

## The GUI library

`modules/gui/` is a widget toolkit written in R#, with the same deal as the HTTP
stack: no external library, no build step, include the files you use. The
portable half draws into a BGRA buffer the program owns; the host half hands
those bytes to the OS. Windows blits with `StretchDIBits` into the window DC,
macOS wraps the same buffer in a `CGBitmapContext` and sets the result as a
layer's contents. Every pixel decision is made above the host, so both platforms
produce the same image for the same widget tree.

```rsx
include "modules/gui/gui_win.rsx";

fn main() -> i32 {
    var app: GApp = zero(GApp);
    if (gui_app_init(&mut app, 720, 520) != 0) {
        return 1;
    }
    gui_set_pad(&mut app, 0, 20, 12);
    gui_add(&mut app, GK_LABEL, 0, "R# / gui");
    let b: i64 = gui_add(&mut app, GK_BUTTON, 0, "press me");
    gui_set_size(&mut app, b, 140, 32);
    gui_render(&mut app);
    gui_win_run(&mut app, "hello");
    gui_app_free(&mut app);
    return 0;
}
```

`gui_add` returns the widget's index in the app's array, and that number is the
id every other call takes: `gui_set_size`, `gui_set_grow`, `gui_set_fill`,
`gui_set_pad`, `gui_set_align`, `gui_set_text`, `gui_set_range`, `gui_set_value`
and the geometry getters. The array only grows, so an id stays valid for the
life of the app. Widgets are a panel, label, button, check, field, slider and
progress bar. A panel arranges its children in a column or a row; fixed sizes
are taken first, `grow` splits the remainder by weight, `fill` stretches across
the other axis, and `align` moves along it. `gui_render` runs the arrangement
and then the paint pass, in that order, and clears `dirty`.

Input comes in through `gui_mouse_move`, `gui_mouse_down`, `gui_mouse_up`,
`gui_wheel` and `gui_key`, and comes back out as a queue drained with
`gui_next_event`: click, toggle, change, submit, focus, blur, timer, close. The
queue holds 32 events and drops the overflow rather than growing. Focus is one
id; a click sets it, a click that lands on no widget clears it, and keys go to
the focused field (backspace, delete, arrows, home, end, return, printable
ASCII). Nothing allocates after `gui_app_init`: 48 widgets in one array, 48
bytes of text each, and the framebuffer is the only heap block the library owns.

Text is a 5x7 bitmap font, 95 glyphs, drawn at integer scale into a 6*scale
cell, so a label is legible at 1:1 and a title can be the same code at scale 3.
The table is generated from the ASCII art in `work/gui/gen_font.py` with
`python work/gui/gen_font.py modules/gui/text/font.rsx`; everything else in the
paint path is rectangles and runs of pixels.

R# has no conditional compilation, so the split between the two hosts is by
file and not by `#ifdef`. `gui.rsx` is the portable core. `gui_win.rsx` and
`gui_mac.rsx` are shims that include the core plus one host, and a program
includes exactly one of them; the core never names a platform symbol. The
Windows host is ordinary Win32: `RegisterClassExA`, `CreateWindowExA`, a
`GWLP_USERDATA` slot holding the app pointer, `BeginPaint`/`EndPaint`, and a
`SetTimer` tick. The macOS host loads AppKit at run time with `dlopen`, builds
its view subclass with `objc_allocateClassPair` and seven `class_addMethod`
calls, and receives the timer through `NSTimer`. Screen coordinates, window
rects and scroll deltas go through `NSInvocation` rather than a direct
`objc_msgSend` with a struct argument: this back end passes aggregates by
pointer and returns them through a hidden pointer. That is the right convention
for R# calls and not the SysV C ABI, which returns a small struct in registers.
`NSRect`, `NSPoint` and `CGFloat` returns are exactly the case that breaks.
`setArgument:atIndex:` and `getReturnValue:` move the bytes, and nothing has to
agree about where they live. Pixels leave the other way:
`CGBitmapContextCreateImage` on the framebuffer, then `[layer setContents:]`.

`gui_win_run` and `gui_mac_run` pump the platform loop until the window closes.
`gui_win_run_hook` and `gui_mac_run_hook` take a tick in milliseconds, an
optional quit deadline, and a `fn(i64, i64)` that receives the app pointer and
the frame number before the paint; that is how a window test drives a click
without a person at the keyboard. The demo window is 720x520 and closes from the
system button, Alt+F4 or the quit button in the scene.

`work\gui\run.cmd` is the suite. It builds and runs a headless test that asserts
ids, geometry, click and toggle events, slider drag, wheel steps, field editing,
and that two renders of an unchanged tree hash the same (`gui_hash` is FNV-1a
over the framebuffer). It builds the hash program and checks the pinned value,
opens a real window for 20 ticks, scripts a click at frame 3, and checks that
the click arrived and the framebuffer changed. Then it builds the Windows demo,
cross-builds the macOS demo and checks the Mach-O image. A run ends with
`gui suite: ok`. The macOS binary is 91,072 bytes and imports libSystem,
libobjc and CoreGraphics; it has not been executed on a Mac from this host, only
checked structurally.

## The math module

`modules/math.rsx` is a floating point and integer math library in plain R# —
no externs, no imports, everything computed from the sign of the bits: sqrt is
a Newton iteration with a fixed 40 steps, sine and cosine are Taylor series
over a range-reduced argument (accurate for |x| up to ~2^52; the reduction
costs bits past that, the classic limit without a split pi/2), tan is the
ratio. Integer side: `isqrt` by Newton, `ipow` by squaring.

```rsx
include "modules/math.rsx";

let r = fsqrt(12345.6789);
let s = fsin(1.0);
let f = ffloor(2.7);
let t = ftan(0.5);
let n = isqrt(12345678);
```

Surface: `PI`, `fsqrt`, `fsin`, `fcos`, `ftan`, `ffloor`, `fceil`, `ftrunc`,
`fround` (half away from zero), `fmod`, `fpow_i` (integer exponent, negative
is the reciprocal), `isqrt`, `ipow`, `fabs`, `fmin`, `fmax`. `fsqrt` of a
negative number is a `-1.0` sentinel, not a trap.

`work\math\run.cmd` builds and runs the suite against reference values from an
independent implementation: sqrt, sin/cos/tan across quadrants including the
large-argument case (`sin(100)`), floor/ceil/trunc/round on both sides of
zero, `fmod` with mixed signs, `fpow_i` including negative exponents, `isqrt`
around perfect squares, `ipow` for exact integers. A run ends with
`math suite: ok`.

## The random module

`modules/rand.rsx` is a PRNG in plain R#: xoshiro256** over a four-word
state. The state words are filled by running an MMIX LCG forward from the
seed (both constants fit a signed 64-bit word, which matters, because R#
integer literals above i64's range cannot be written). Everything else is
shifts, rotates and two multiplies. No externs, no allocations, no globals —
the state is a struct the caller owns.

```rsx
include "modules/rand.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    var r: Rng = zero(Rng);
    rand_seed(&mut r, 42);
    printf("%llu\n", rand_next(&mut r));
    return 0;
}
```

Prints `12347341778764037776`. The rest of the surface: `rand_below(r, n)`
for `[0, n)`, `rand_range(r, lo, hi)` for `[lo, hi)`, `rand_frac(r)` for
`[0, 1)`, and `rand_shuffle(r, ptr, n)` for Fisher–Yates in place.

`rand_below` rejects against a computed threshold, so `n` need not be a power
of two and the result is exactly uniform, not divided through a double.
`rand_frac` takes the top 53 bits over 2^53; `rand_below(r, 0)` returns 0.

`work\rand\run.cmd` builds the headless test and checks the seeded stream
against values from an independent implementation of the same algorithm: the
first ten `rand_below(1000)` draws for seed 42, the first five `rand_frac`
outputs, a full shuffle of `0..9`, determinism across two instances of the
same seed, divergence of different seeds, the range bounds and the
`n = 0` guard. A run ends with `rand suite: ok`.

## PAINT

`work\gui\paint.rsx` is a paint program written in R# against the widget
library — and against one new widget that library grew for it: `GK_CANVAS`.
The canvas owns a malloc'd BGRA grid the size of the widget (656x336), filled
white at setup; drawing goes into the grid, not into the window buffer, and
`gui_render` blits grid → surface each frame like any other widget. The brush
is square, `bsize` pixels across, and strokes between mouse moves are
Bresenham-interpolated so a fast drag stays continuous. The canvas also holds
its brush color word and size, so there is no global state anywhere in the
program.

The pieces: the toolbar is eight color buttons (K R O Y G B M W, where W is
also the eraser), brush size − and + (1..8), clear, save and quit. The window
is 720x520 and closes the usual ways — system button, Alt+F4, or quit. Drag on
the canvas to paint. `save` writes a 24-bit BMP (`paint.bmp` next to the
program): BGR rows bottom-up, stride 1968, file size exactly 661,302 bytes —
`w*3` stays 4-aligned so there is no row padding to get wrong.

`paint_scene.rsx` holds everything both binaries share: the palette, the BMP
writer, the status line (`brush N  color X`, updated on every change), and the
click dispatch. `paint.rsx` is the interactive shell (`gui_win_run`).
`t_paint.rsx` is the headless self-test: it builds the same scene, drives a
scripted stroke across the canvas with `gui_mouse_*`, clicks save at frame 4,
then verifies the file exists, starts with `BM`, and is the exact expected
size. The suite runs it as `[6/6]` in `work\gui\run.cmd`.

The canvas widget itself is portable core — it touches nothing platform
specific — so the macOS demo image still cross-builds. The PAINT program does
not: its BMP writer calls `CreateFileA`/`WriteFile`/`CloseHandle`, and those
are Windows imports by design.

## License

MIT. See `LICENSE`.
