#!/usr/bin/env bash
set -euo pipefail

cmd=install
prefix=""
no_build=0
no_check=0
skip_path=0
quiet=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix | -p)
      shift
      [ $# -gt 0 ] || { echo "basicr: --prefix needs a directory" >&2; exit 2; }
      prefix="$1"
      ;;
    --prefix=*) prefix="${1#--prefix=}" ;;
    --no-build) no_build=1 ;;
    --no-check) no_check=1 ;;
    --skip-path) skip_path=1 ;;
    --quiet | -q) quiet=1 ;;
    --help | -h) cmd=help ;;
    -*) echo "basicr: unknown flag '$1'" >&2; exit 2 ;;
    *) cmd="$1" ;;
  esac
  shift
done

say() {
  [ "$quiet" = 1 ] || printf 'basicr: %s\n' "$*"
}

die() {
  printf 'basicr: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'TEXT'
basicr - install the R# toolchain

  basicr [install] [--prefix <dir>] [--no-build] [--no-check] [--skip-path] [--quiet]
  basicr check     [--prefix <dir>] [--quiet]
  basicr uninstall [--prefix <dir>] [--quiet]
  basicr env       [--prefix <dir>]
TEXT
  exit 0
}

here=$(cd -- "$(dirname -- "$0")" && pwd -P)
root=${RSC_ROOT:-$(cd -- "$here/.." && pwd -P)}

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) die "windows host - run basicr.cmd" ;;
  Darwin) host=macos ;;
  Linux) host=linux ;;
  *) die "unsupported host $(uname -s)" ;;
esac

if [ -z "$prefix" ]; then
  if [ -n "${RSC_PREFIX:-}" ]; then
    prefix=$RSC_PREFIX
  elif [ "$host" = macos ]; then
    prefix="$HOME/Library/Application Support/rsharp"
  else
    prefix="${XDG_DATA_HOME:-$HOME/.local/share}/rsharp"
  fi
fi
case "$prefix" in
  /*) ;;
  *) prefix="$PWD/$prefix" ;;
esac
prefix=${prefix%/}

toolchain="$prefix/toolchain"
bindir="$prefix/bin"

if [ "$cmd" = help ]; then
  usage
fi

guard_prefix() {
  case "$prefix" in
    "" | / | "$HOME") die "refusing to touch '$prefix'" ;;
  esac
}

missing_build() {
  local miss=""
  command -v cargo >/dev/null 2>&1 || miss="$miss cargo"
  command -v ocamlopt >/dev/null 2>&1 || miss="$miss ocamlopt"
  [ -z "$miss" ] || die "the build needs$miss"
}

build_tree() {
  [ -f "$root/build.sh" ] || die "no build.sh under $root"
  missing_build
  say "building the toolchain in $root"
  ( cd -- "$root" && bash ./build.sh )
}

pick() {
  local name=$1
  local out=$2
  local src
  case "$name" in
    rsc) src="$root/frontend/target/release/rsc" ;;
    rscb) src="$root/backend/rscb" ;;
    cdc) src="$root/cdc/target/release/cdc" ;;
    mini) src="$root/mini/mini" ;;
    *) src="" ;;
  esac
  [ -x "$src" ] || return 1
  cp "$src" "$out"
  chmod 755 "$out"
}

write_driver() {
  cat >"$bindir/rsc" <<'DRIVER'
#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd -P)
tc="$here/../toolchain"
front="$tc/rsc"
back="$tc/rscb"
[ -x "$front" ] || { echo "rsc: missing $front" >&2; exit 1; }
[ -x "$back" ] || { echo "rsc: missing $back" >&2; exit 1; }

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) host=windows ;;
  *) host=macos ;;
esac

tgt="${RSC_TARGET:-$host}"
if [ "${1:-}" = "-t" ]; then
  tgt="${2:-}"
  shift 2
fi

[ $# -ge 1 ] || { echo "usage: rsc [-t windows|macos] <file.rsx> [out]" >&2; exit 2; }

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

"$front" "$src" -o "$ir"
"$back" "$ir" -o "$out" -s "$src" -t "$tgt"
rm -f "$ir"

case "$tgt" in
  macos | mac | darwin | osx) chmod 755 "$out" 2>/dev/null || true ;;
esac

echo "built $out"
DRIVER
  chmod 755 "$bindir/rsc"
}

write_tool() {
  local name=$1
  cat >"$bindir/$name" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
here=\$(cd -- "\$(dirname -- "\$0")" && pwd -P)
exec "\$here/../toolchain/$name" "\$@"
WRAP
  chmod 755 "$bindir/$name"
}

write_env() {
  cat >"$prefix/env.sh" <<ENV
case ":\$PATH:" in
  *":$bindir:"*) ;;
  *) PATH="$bindir:\$PATH" ;;
esac
export PATH
ENV
}

profile_line() {
  printf '. "%s/env.sh"\n' "$prefix"
}

rc_files() {
  local files="$HOME/.profile"
  case "$(basename "${SHELL:-/bin/sh}")" in
    zsh) printf '%s %s\n' "$files" "$HOME/.zshrc" ;;
    bash) printf '%s %s\n' "$files" "$HOME/.bashrc" ;;
    *) printf '%s\n' "$files" ;;
  esac
}

wire_profile() {
  local line
  line=$(profile_line)
  local f
  for f in $(rc_files); do
    touch "$f"
    if grep -Fxq "$line" "$f"; then
      say "PATH already wired in $f"
      continue
    fi
    grep -Fvx "$line" "$f" >"$f.basicr" || true
    mv "$f.basicr" "$f"
    printf '%s\n' "$line" >>"$f"
    say "PATH wired in $f"
  done
}

unwire_profile() {
  local line
  line=$(profile_line)
  local f
  for f in $(rc_files); do
    [ -f "$f" ] || continue
    grep -Fvx "$line" "$f" >"$f.basicr" || true
    mv "$f.basicr" "$f"
  done
}

verify() {
  local rsc="$bindir/rsc"
  [ -x "$rsc" ] || die "no rsc under $bindir; run basicr install"
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/basicr.XXXXXX")
  cat >"$dir/hello.rsx" <<'SRC'
extern fn puts(s: ptr<u8>) -> i32;

fn main() -> i32 {
    puts("hello from R#");
    return 0;
}
SRC
  if ! "$rsc" "$dir/hello.rsx" "$dir/hello" >"$dir/build.log" 2>&1; then
    cat "$dir/build.log" >&2
    rm -rf "$dir"
    die "the compiler did not build hello.rsx"
  fi
  if [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = x86_64 ]; then
    local out
    out=$("$dir/hello")
    if [ "$out" != "hello from R#" ]; then
      rm -rf "$dir"
      die "hello printed '$out'"
    fi
    say "check ok: hello from R#"
  else
    local magic
    magic=$(od -An -tx1 -N4 "$dir/hello" | tr -d ' \n')
    case "$magic" in
      cffaedfe | feedface) say "check ok: x86-64 mach-o image from hello.rsx" ;;
      *)
        rm -rf "$dir"
        die "hello.rsx produced '$magic'"
        ;;
    esac
  fi
  rm -rf "$dir"
}

install_all() {
  guard_prefix
  say "prefix $prefix"
  local front="$root/frontend/target/release/rsc"
  local back="$root/backend/rscb"
  if [ ! -x "$front" ] || [ ! -x "$back" ]; then
    if [ "$no_build" = 1 ]; then
      die "the toolchain is not built; drop --no-build or run ./build.sh"
    fi
    build_tree
  fi
  [ -x "$root/frontend/target/release/rsc" ] || die "missing $root/frontend/target/release/rsc"
  [ -x "$root/backend/rscb" ] || die "missing $root/backend/rscb"

  mkdir -p "$toolchain" "$bindir"
  local names=""
  local n
  for n in rsc rscb cdc mini; do
    if pick "$n" "$toolchain/$n"; then
      if [ -z "$names" ]; then
        names="$n"
      else
        names="$names, $n"
      fi
    elif [ "$n" = rsc ] || [ "$n" = rscb ]; then
      die "missing $n in the build"
    fi
  done
  if [ -f "$root/LICENSE" ]; then
    cp "$root/LICENSE" "$prefix/LICENSE"
  fi

  write_driver
  for n in rscb cdc mini; do
    if [ -x "$toolchain/$n" ]; then
      write_tool "$n"
    fi
  done
  write_env
  if [ "$skip_path" = 0 ]; then
    wire_profile
  fi
  say "installed $names"
  if [ "$no_check" = 0 ]; then
    verify
  fi
  if [ "$skip_path" = 0 ]; then
    say "open a new shell to pick up PATH, or run . $prefix/env.sh now"
  fi
}

case "$cmd" in
  install) install_all ;;
  check)
    say "prefix $prefix"
    verify
    ;;
  uninstall)
    guard_prefix
    say "prefix $prefix"
    unwire_profile
    rm -rf "$prefix"
    say "removed"
    ;;
  env) profile_line ;;
  *) usage ;;
esac
