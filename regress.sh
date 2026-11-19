#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"
mkdir -p build

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ext=.exe; host=windows; vmexe=./backend/rscvm.exe ;;
  *) ext=; host=macos; vmexe=./backend/rscvm ;;
esac

fail=0
for f in examples/*.rsx; do
  n="$(basename "$f" .rsx)"

  if [ "$n" = bench_mac ]; then
    if ! bash ./rsc.sh -t macos "$f" "build/$n" >/dev/null 2>"build/$n.err"; then
      echo "FAIL-BUILD $n"
      sed 's/^/  /' "build/$n.err"
      fail=1
      continue
    fi
    if [ "$host" = macos ]; then
      "./build/$n" >/dev/null 2>&1
      echo "$n exit=$? (macos image)"
    else
      echo "$n built (macos image, not run here)"
    fi
    continue
  fi

  if ! bash ./rsc.sh "$f" "build/$n$ext" >/dev/null 2>"build/$n.err"; then
    echo "FAIL-BUILD $n"
    sed 's/^/  /' "build/$n.err"
    fail=1
    continue
  fi
  "./build/$n$ext" >"build/$n.out" 2>&1
  nat=$?
  cat "build/$n.out"

  if [ "$n" = bench ]; then
    echo "$n exit=$nat (vm parity skipped, long-running)"
    continue
  fi

  if ! bash ./rsc.sh --vm "$f" "build/$n.rvm" >/dev/null 2>"build/$n.verr"; then
    echo "FAIL-VM-BUILD $n"
    sed 's/^/  /' "build/$n.verr"
    fail=1
    continue
  fi
  "$vmexe" "build/$n.rvm" >"build/$n.vout" 2>&1
  vmr=$?

  if [ "$nat" != "$vmr" ]; then
    echo "FAIL-VM-EXIT $n native=$nat vm=$vmr"
    fail=1
    continue
  fi
  if ! cmp -s "build/$n.out" "build/$n.vout"; then
    echo "FAIL-VM-OUT $n"
    diff "build/$n.out" "build/$n.vout" | head -n 12 | sed 's/^/  /'
    fail=1
    continue
  fi
  echo "$n exit=$nat"
done

echo
bash ./mini/test.sh || fail=1

exit "$fail"
