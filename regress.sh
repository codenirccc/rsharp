#!/usr/bin/env bash
# regress.sh - the posix twin of regress.cmd. Same examples, same order.
set -uo pipefail

cd "$(dirname "$0")"
mkdir -p build

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ext=.exe; host=windows ;;
  *) ext=; host=macos ;;
esac

fail=0
for f in examples/*.rsx; do
  n="$(basename "$f" .rsx)"

  # mach_absolute_time only resolves against a Mach-O image, so this one is
  # built for macOS on every host and run only where that image can execute.
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
  "./build/$n$ext"
  echo "$n exit=$?"
done

echo
bash ./mini/test.sh || fail=1

exit "$fail"
