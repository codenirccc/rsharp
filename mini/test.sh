#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"
here="$(pwd)"
root="$(cd .. && pwd)"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ext=.exe; tgt=windows ;;
  *) ext=; tgt=macos ;;
esac

back="$root/backend/rscb"
[ -x "$back" ] || back="$back.exe"

if command -v cygpath >/dev/null 2>&1; then
  winpath() { cygpath -w "$1"; }
else
  winpath() { printf '%s' "$1"; }
fi

bash "$here/build.sh" >/dev/null || { echo "FAIL-BUILD mini"; exit 1; }

mkdir -p "$root/build"
fail=0

same() {
  if command -v cmp >/dev/null 2>&1; then
    cmp -s "$1" "$2"
  else
    local a b
    IFS= read -r -d '' a < "$1" || true
    IFS= read -r -d '' b < "$2" || true
    [ "$a" = "$b" ]
  fi
}

for f in examples/*.mini; do
  n="$(basename "$f" .mini)"
  ok=1

  if ! "$here/mini$ext" --aot "$(winpath "$f")" -o "$(winpath "$root/build/$n$ext")" >/dev/null 2>&1; then
    echo "FAIL-AOT $n"
    fail=1
    ok=0
  fi

  if [ "$ok" = "1" ]; then
    "$root/build/$n$ext" > "$root/build/$n.out" 2>/dev/null
    if ! same "$root/build/$n.out" "examples/$n.out"; then
      echo "FAIL-RUN $n"
      fail=1
      ok=0
    fi
  fi

  if [ "$ok" = "1" ]; then
    if "$here/mini$ext" --jit "$(winpath "$f")" > "$root/build/$n.jit" 2>/dev/null \
        && same "$root/build/$n.jit" "examples/$n.out"; then
      :
    else
      echo "FAIL-JIT $n"
      fail=1
      ok=0
    fi
  fi

  if [ "$ok" = "1" ]; then
    if ! "$here/mini$ext" < "$f" > "$root/build/$n.rsi"; then
      echo "FAIL-FILTER $n"
      fail=1
      ok=0
    elif ! "$back" "$(winpath "$root/build/$n.rsi")" -o "$(winpath "$root/build/$n.f$ext")" -t "$tgt" >/dev/null 2>&1; then
      echo "FAIL-LINK $n"
      fail=1
      ok=0
    fi
  fi

  if [ "$ok" = "1" ]; then
    echo "ok $n"
  fi
done

"$here/mini$ext" -v > "$root/build/banner.txt" 2>&1
if grep -q "mini Compiler for R# 1.2" "$root/build/banner.txt" \
    && grep -q "jit + aot - one file - no runtime" "$root/build/banner.txt"; then
  echo "ok banner"
else
  echo "FAIL-BANNER"
  fail=1
fi

exit "$fail"
