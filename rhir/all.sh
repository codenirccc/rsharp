#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

cargo build --release || exit 1

bin=target/release/rhirc
[ -x "$bin" ] || bin=target/release/rhirc.exe

mkdir -p tests
rm -f tests/*.out*.rhir tests/*.exe

canrun=0
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) canrun=1 ;;
  *) command -v wine >/dev/null 2>&1 && canrun=1 ;;
esac

runpe() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) "$1" ;;
    *) wine "$1" 2>/dev/null ;;
  esac
}

fail=0
for f in tests/*.rhir; do
  case "$f" in *.out.rhir) continue ;; esac
  n="$(basename "$f" .rhir)"
  echo "== $n.rhir"
  "$bin" "$f" -o "tests/$n.exe" >/dev/null || exit 1
  "$bin" "$f" --emit-ir > "tests/$n.out.rhir" || exit 1
  "$bin" "tests/$n.out.rhir" -o "tests/$n.rt.exe" >/dev/null || exit 1

  if [ "$canrun" = 1 ]; then
    runpe "tests/$n.exe" >/dev/null 2>&1
    a=$?
    runpe "tests/$n.rt.exe" >/dev/null 2>&1
    b=$?
    echo "exit=$a roundtrip=$b"
    [ "$a" = "$b" ] || fail=1
  else
    echo "compiled (PE image, nothing here can run it)"
  fi
done

exit "$fail"
