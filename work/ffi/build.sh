#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/../../build"
mkdir -p "$out"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    ext=.dll
    pic=
    ;;
  Darwin)
    ext=.dylib
    pic=-fPIC
    ;;
  *)
    ext=.so
    pic=-fPIC
    ;;
esac

cc -O2 -shared $pic -o "$out/c_add$ext" "$here/c_add.c"
c++ -O2 -shared $pic -o "$out/cpp_shim$ext" "$here/cpp_shim.cpp"

echo "built build/c_add$ext and build/cpp_shim$ext"
