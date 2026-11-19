#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exe="$here/build/rmake"

chmod +x "$here/rsc.sh" 2>/dev/null || true

stale=0
if [ "${1:-}" = "bootstrap" ]; then
    stale=1
    shift
    if [ $# -eq 0 ]; then
        "$here/rsc.sh" "$here/tools/rmake/main.rsx" "$exe"
        exit 0
    fi
fi

if [ "$stale" = "0" ]; then
    if [ ! -x "$exe" ]; then
        stale=1
    else
        newer="$(find "$here/tools/rmake" -name '*.rsx' -newer "$exe" -print -quit 2>/dev/null || true)"
        if [ -n "$newer" ]; then
            stale=1
        fi
    fi
fi

if [ "$stale" = "1" ]; then
    "$here/rsc.sh" "$here/tools/rmake/main.rsx" "$exe"
fi

start="$PWD"
mkdir -p .rmake
args="$PWD/.rmake/cmd.txt"
{
    echo "--rsc"
    echo "$here/rsc.sh"
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@"
    fi
} > "$args"

export RMAKE_CMD="$args"
if command -v cygpath >/dev/null 2>&1; then
    RMAKE_CMD="$(cygpath -w "$args")"
fi
export RMAKE_CMD

case "${1:-}" in
    help | --help | -h)
        exec "$exe"
        ;;
esac

export RMAKE_SEEK=1
while :; do
    rc=0
    "$exe" || rc=$?
    if [ "$rc" -ne 3 ]; then
        exit "$rc"
    fi
    before="$PWD"
    cd ..
    if [ "$PWD" = "$before" ]; then
        printf 'rmake: no RMakefile in %s or any parent\n' "$start" >&2
        printf 'rmake: pass --manifest PATH to name a build file\n' >&2
        exit 1
    fi
done
