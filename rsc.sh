#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

front="$here/frontend/target/release/rsc"
back="$here/backend/rscb"
[ -x "$front" ] || front="$front.exe"
[ -x "$back" ] || back="$back.exe"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) host=windows ;;
  Darwin) host=macos ;;
  *) host=linux ;;
esac

tgt="${RSC_TARGET:-$host}"
vm=
if [ "${1:-}" = "--vm" ]; then
  vm=1
  shift
fi
if [ "${1:-}" = "-t" ] && [ -z "$vm" ]; then
  tgt="${2:-}"
  shift 2
fi

[ -x "$front" ] || { echo "rsc: front end not built - run ./build.sh" >&2; exit 1; }
[ -x "$back" ] || { echo "rsc: back end not built (backend/build.sh)" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: rsc.sh [--vm] [-t windows|macos|linux] <file.rsx> [out]" >&2; exit 2; }

case "$tgt" in
  macos | mac | darwin | osx | linux | elf | gnu) ext= ;;
  *) ext=.exe ;;
esac
if [ -n "$vm" ]; then ext=.rvm; fi

src="$1"
stem="$(basename "${src%.*}")"
dir="$(cd "$(dirname "$src")" && pwd)"
out="${2:-$dir/$stem$ext}"

if [ -n "$(dirname "$out")" ]; then
  mkdir -p "$(dirname "$out")"
fi

ir="$dir/$stem.rsi"

if command -v cygpath >/dev/null 2>&1; then
  wsrc="$(cygpath -w "$src")"
  wir="$(cygpath -w "$ir")"
  wout="$(cygpath -w "$out")"
else
  wsrc="$src"
  wir="$ir"
  wout="$out"
fi

"$front" "$wsrc" -o "$wir"
if [ -n "$vm" ]; then
  "$back" "$wir" --vm -o "$wout" -s "$wsrc"
else
  "$back" "$wir" -o "$wout" -s "$wsrc" -t "$tgt"
fi
rm -f "$ir"

case "$tgt" in
  macos | mac | darwin | osx | linux | elf | gnu) [ -n "$vm" ] || chmod 755 "$out" 2>/dev/null || true ;;
esac

echo "built $out"
