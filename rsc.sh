#!/usr/bin/env bash
# rsc.sh - the posix driver. Same contract as rsc.cmd: [-t target] <file.rsx> [out]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

front="$here/frontend/target/release/rsc"
back="$here/backend/rscb"
[ -x "$front" ] || front="$front.exe"
[ -x "$back" ] || back="$back.exe"

# No ELF writer, so every non-Windows host defaults to the Mach-O target.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) host=windows ;;
  *) host=macos ;;
esac

tgt="${RSC_TARGET:-$host}"
if [ "${1:-}" = "-t" ]; then
  tgt="${2:-}"
  shift 2
fi

[ -x "$front" ] || { echo "rsc: front end not built - run ./build.sh" >&2; exit 1; }
[ -x "$back" ] || { echo "rsc: back end not built (backend/build.sh)" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: rsc.sh [-t windows|macos] <file.rsx> [out]" >&2; exit 2; }

case "$tgt" in
  macos | mac | darwin | osx) ext= ;;
  *) ext=.exe ;;
esac

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
"$back" "$wir" -o "$wout" -s "$wsrc" -t "$tgt"
rm -f "$ir"

case "$tgt" in
  macos | mac | darwin | osx) chmod 755 "$out" 2>/dev/null || true ;;
esac

echo "built $out"
