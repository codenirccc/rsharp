set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

[ $# -ge 1 ] || { echo "usage: run.sh <file.mini> [out]" >&2; exit 2; }

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ext=.exe ;;
  *) ext= ;;
esac

if command -v cygpath >/dev/null 2>&1; then
  winpath() { cygpath -w "$1"; }
else
  winpath() { printf '%s' "$1"; }
fi

bash "$here/build.sh" >/dev/null

in="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
if [ $# -ge 2 ]; then
  out="$2"
else
  out="${in%.*}$ext"
fi

"$here/mini$ext" --aot "$(winpath "$in")" -o "$(winpath "$out")"
echo "built $out"
