#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
root="$(cd .. && pwd)"

plat=mac
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) plat=win ;;
esac

want="${1:-$plat}"
case "$want" in
  windows | win) host=win; tgt=windows; ext=.exe ;;
  macos | mac | darwin | osx) host=mac; tgt=macos; ext= ;;
  *) echo "usage: build.sh [windows|macos]" >&2; exit 2 ;;
esac

native=$plat
out="mini$ext"
[ "$host" = "$native" ] || out="$root/build/mini_$host"

mkdir -p "$root/build"
src="$root/build/mini_$host.rsx"
cat src/mini.rsx "src/host_$host.rsx" > "$src"

bash "$root/rsc.sh" -t "$tgt" "$src" "$out"
