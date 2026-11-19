#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    ucrt=
    mgw=
    for cand in /ucrt64:/mingw64 /c/msys64/ucrt64:/c/msys64/mingw64 /d/msys64/ucrt64:/d/msys64/mingw64; do
      if [ -d "${cand%%:*}/bin" ]; then
        ucrt="${cand%%:*}"
        mgw="${cand##*:}"
        break
      fi
    done
    if [ -n "$ucrt" ]; then
      export PATH="$ucrt/bin:$PATH"
      [ -d "$mgw/bin" ] && export PATH="$mgw/bin:$PATH"
      if [ -z "${OCAMLLIB:-}" ] && [ -d "$ucrt/lib/ocaml" ]; then
        OCAMLLIB="$ucrt/lib/ocaml"
      fi
    fi
    if [ -z "${OCAMLLIB:-}" ]; then
      if [ -d /ucrt64/lib/ocaml ]; then
        OCAMLLIB=/ucrt64/lib/ocaml
      else
        echo "backend/build.sh: cannot locate the ucrt64 OCaml stdlib - set OCAMLLIB" >&2
        exit 1
      fi
    fi
    EXE=.exe
    ;;
  *)
    if [ -z "${OCAMLLIB:-}" ]; then
      OCAMLLIB=$(ocamlopt -where 2>/dev/null || ocamlc -where)
    fi
    EXE=
    ;;
esac

OCAMLOPT=${OCAMLOPT:-ocamlopt}

echo "==> compiling back end with $("$OCAMLOPT" -version 2>/dev/null || echo 'ocamlopt')"

rm -f ./*.cmi ./*.cmx ./*.o

"$OCAMLOPT" -I "$OCAMLLIB" -w +a-4-9-40-41-42-44-45-70 -o "rscb$EXE" \
  sexp.ml \
  ast.ml \
  fold.ml \
  lto.ml \
  range.ml \
  parse.ml \
  typeck.ml \
  mono.ml \
  borrow.ml \
  x64.ml \
  target.ml \
  pe.ml \
  macho.ml \
  elf.ml \
  cg.ml \
  vm.ml \
  main.ml

echo "==> rscb$EXE built"

"$OCAMLOPT" -I "$OCAMLLIB" -w +a-4-9-40-41-42-44-45-70 -o "rscvm$EXE" \
  sexp.ml \
  ast.ml \
  fold.ml \
  lto.ml \
  range.ml \
  parse.ml \
  typeck.ml \
  mono.ml \
  borrow.ml \
  x64.ml \
  target.ml \
  pe.ml \
  macho.ml \
  cg.ml \
  vm.ml \
  vmrun.ml

echo "==> rscvm$EXE built"
