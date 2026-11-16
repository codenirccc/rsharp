#!/usr/bin/env bash
# build.sh - the posix entry point, mirror of build.cmd/build.ps1.
set -euo pipefail

cd "$(dirname "$0")"

clean=""
case "${1:-}" in
  -Clean | --clean | -clean) clean=1 ;;
esac

if [ -n "$clean" ]; then
  echo "==> cleaning"
  (cd frontend && cargo clean)
  (cd cdc && cargo clean)
  rm -f backend/rscb backend/rscb.exe mini/mini mini/mini.exe
fi

echo "==> front end (rust)"
(cd frontend && cargo build --release)

echo "==> back end (ocaml)"
./backend/build.sh

echo "==> cdc (rust)"
(cd cdc && cargo build --release)

echo
echo "all three are up. try:"
echo "  ./rsc.sh examples/hello.rsx"
echo "  ./rsc.sh examples/fib.rsx build/fib"
echo "  ./rsc.sh -t windows examples/hello.rsx build/hello.exe"
echo "  mini/run.sh mini/examples/fib.mini"
echo "  cdc/target/release/cdc new demo"
