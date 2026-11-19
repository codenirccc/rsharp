#!/usr/bin/env bash
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$here"

ver=226
out="$here/dist"
stage="$out/.stage"

die() {
    printf 'dist: %s\n' "$*" >&2
    exit 1
}

need() {
    [ -f "$1" ] || die "missing $1 - run make tools first"
}

need build/rmake.exe
need build/rmake_linux
need build/rmake_mac

rm -rf "$out"
mkdir -p "$out"

cer=""
if [ -f sign.ps1 ] && command -v powershell >/dev/null 2>&1; then
    mkdir -p "$out/.stage"
    list="$out/.stage/sign.txt"
    : >"$list"
    for f in \
        "$here/build/rmake.exe" \
        "$here/frontend/target/release/rsc.exe" \
        "$here/backend/rscb.exe" \
        "$here/backend/rscvm.exe" \
        "$here/cdc/target/release/cdc.exe" \
        "$here/mini/mini.exe"; do
        [ -f "$f" ] && printf '%s\n' "$(cygpath -w "$f")" >>"$list"
    done
    if [ -s "$list" ]; then
        printf 'dist: signing\n'
        sigdir="${LOCALAPPDATA:-$HOME/AppData/Local}/rsharp/signing"
        mkdir -p "$sigdir"
        cp sign.ps1 "$sigdir/sign.ps1"
        powershell -NoProfile -ExecutionPolicy Bypass \
            -File "$(cygpath -w "$sigdir/sign.ps1")" \
            -Store "$(cygpath -w "$sigdir")" \
            -List "$(cygpath -w "$list")" -Trust || die "signing failed"
    fi
    sigdir="${LOCALAPPDATA:-$HOME/AppData/Local}/rsharp/signing"
    if [ -f "$sigdir/rsharp-selfsigned.cer" ]; then
        cer="$sigdir/rsharp-selfsigned.cer"
        cp "$cer" "$out/rsharp-selfsigned.cer"
    fi
fi

cp build/rmake.exe "$out/rmake-v$ver-windows-x86_64.exe"
cp build/rmake_linux "$out/rmake-v$ver-linux-x86_64"
cp build/rmake_mac "$out/rmake-v$ver-macos-x86_64"
chmod 755 "$out/rmake-v$ver-linux-x86_64" "$out/rmake-v$ver-macos-x86_64"

take() {
    if [ -f "$1" ]; then
        cp "$1" "$2"
        return 0
    fi
    return 1
}

win="$stage/win"
mkdir -p "$win/bin" "$win/basicr"
cp build/rmake.exe "$win/bin/rmake.exe"
take frontend/target/release/rsc.exe "$win/bin/" || die "missing frontend/target/release/rsc.exe"
take backend/rscb.exe "$win/bin/" || die "missing backend/rscb.exe"
take backend/rscvm.exe "$win/bin/" || true
take cdc/target/release/cdc.exe "$win/bin/" || true
take mini/mini.exe "$win/bin/" || true
take basicr/basicr.ps1 "$win/basicr/"
take basicr/basicr.cmd "$win/basicr/"
take LICENSE "$win/"
if [ -n "$cer" ]; then
    cp "$cer" "$win/"
fi

zip=0
if command -v zip >/dev/null 2>&1; then
    ( cd "$win" && zip -qr "$out/rsharp-v$ver-windows-x86_64.zip" . )
    zip=1
elif command -v powershell >/dev/null 2>&1; then
    wsrc=$(cygpath -w "$win" 2>/dev/null || printf '%s' "$win")
    wdst=$(cygpath -w "$out/rsharp-v$ver-windows-x86_64.zip" 2>/dev/null || printf '%s' "$out/rsharp-v$ver-windows-x86_64.zip")
    powershell -NoProfile -Command \
        "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::CreateFromDirectory('$wsrc', '$wdst', [System.IO.Compression.CompressionLevel]::Optimal, \$false)" \
        >/dev/null
    zip=1
fi
[ "$zip" = 1 ] || die "no zip and no powershell to build the windows bundle"

unix="$stage/rsharp"
mkdir -p "$unix"
tar -C "$(dirname -- "$here")" -cf - \
    --exclude='rsharp/dist' \
    --exclude='rsharp/build' \
    --exclude='rsharp/.rmake' \
    --exclude='rsharp/.git' \
    --exclude='rsharp/frontend/target' \
    --exclude='rsharp/cdc/target' \
    --exclude='rsharp/rhir/target' \
    --exclude='*.cmi' \
    --exclude='*.cmx' \
    --exclude='*.o' \
    --exclude='rscb' \
    --exclude='rscb.exe' \
    --exclude='rscvm' \
    --exclude='rscvm.exe' \
    --exclude='mini.exe' \
    --exclude='*.rsi' \
    --exclude='__pycache__' \
    rsharp | tar -C "$stage" -xf -
mkdir -p "$unix"
cp build/rmake_linux "$unix/rmake-v$ver-linux-x86_64"
cp build/rmake_mac "$unix/rmake-v$ver-macos-x86_64"
chmod 755 "$unix/rmake-v$ver-linux-x86_64" "$unix/rmake-v$ver-macos-x86_64"
tar -C "$stage" -czf "$out/rsharp-v$ver-src.tar.gz" rsharp

rm -rf "$stage"

cd "$out"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum ./* >SHA256SUMS
else
    shasum -a 256 ./* >SHA256SUMS
fi

printf '\n'
cd "$here"
for f in "$out"/*; do
    case "$f" in
        */SHA256SUMS) continue ;;
    esac
    printf '  %-44s %9s\n' "$(basename "$f")" "$(wc -c <"$f" | tr -d ' ')"
done
printf '\n'
