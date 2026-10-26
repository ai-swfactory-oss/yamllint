#!/usr/bin/env bash
# Builds the self-contained tree for one platform, on that platform: the pinned
# CPython (scripts/fetch-python.sh) with the hash-locked wheels of
# locks/<platform>.txt installed into it, and one stub per tool in bin/.
#
#   scripts/build.sh <outdir> <platform>
#
# - pip runs with --require-hashes --only-binary=:all: --no-deps: every file is
#   checked against the lock, nothing is compiled from source, and nothing
#   outside the lock is installed; `pip check` then proves the lock is complete.
# - pip itself and the interpreter's other console scripts (absolute shebangs,
#   unused) are removed; symlinks are replaced by copies, because npm pack
#   drops symlinks.
# - bin/<tool> is a POSIX sh stub: exec <package>/python/bin/python3 -I -m
#   <module>. -I isolates it from PYTHONPATH, the user site and the cwd.
# - The licence texts of every installed distribution go to LICENSES/<dist>/.
#
# Result: <outdir>/{bin,python,LICENSES}
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
mkdir -p "${1:?usage: build.sh <outdir> <platform>}"
out=$(cd "$1" && pwd)
platform=${2:?usage: build.sh <outdir> <platform>}
lock="${LOCK_DIR:-$root/locks}/$platform.txt"

if ! grep -qE '^[A-Za-z0-9_.-]+==[^ ]+ --hash=sha256:[0-9a-f]{64}' "$lock" || grep -q PENDING "$lock"; then
  echo "build: $lock is not a complete hash lock (regenerate it with the lock workflow)" >&2; exit 1
fi

bash "$root/scripts/fetch-python.sh" "$out" "$platform"
py="$out/python/bin/python3"
"$py" -I -m pip install --disable-pip-version-check --no-cache-dir --no-warn-script-location \
  --require-hashes --only-binary=:all: --no-deps --no-compile -r "$lock"
"$py" -I -m pip check

site=$("$py" -I -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
for info in "$site"/*.dist-info; do
  dist=$(basename "$info" .dist-info)
  dist=${dist%-*}
  [ "$dist" = pip ] && continue
  mkdir -p "$out/LICENSES/$dist"
  if [ -d "$info/licenses" ]; then
    cp -R "$info/licenses/." "$out/LICENSES/$dist/"
  fi
  find "$info" -maxdepth 1 -type f \( -iname 'LICEN[CS]E*' -o -iname 'COPYING*' -o -iname 'NOTICE*' -o -iname 'AUTHORS*' \) \
    -exec cp {} "$out/LICENSES/$dist/" \;
  if [ -z "$(ls -A "$out/LICENSES/$dist")" ]; then
    echo "build: $dist ships no licence file in its wheel" >&2; exit 1
  fi
done

"$py" -I -m pip uninstall --disable-pip-version-check -y pip
find "$out/python/bin" -mindepth 1 -maxdepth 1 ! -name 'python3*' ! -name python -exec rm -f {} +
rm -f "$out/python/bin/python3-config" "$out/python/bin/python3."*-config

# npm pack drops symlinks: replace each with a copy of its target.
find "$out/python" -type l | while read -r link; do
  target=$(cd "$(dirname "$link")" && cd "$(dirname "$(readlink "$link")")" && pwd -P)/$(basename "$(readlink "$link")")
  rm "$link"
  cp -R "$target" "$link"
done
test -z "$(find "$out/python" -type l)" || { echo "build: symlinks left in the tree" >&2; exit 1; }

mkdir -p "$out/bin"
for tool in $(jq -r '.tools | keys[]' "$manifest"); do
  module=$(jq -er --arg t "$tool" '.tools[$t]' "$manifest")
  cat >"$out/bin/$tool" <<EOF
#!/bin/sh
# $tool on the CPython bundled in this package, isolated from the host Python (-I).
here=\$(cd "\$(dirname "\$0")" && pwd -P)
exec "\$here/../python/bin/python3" -I -m $module "\$@"
EOF
  chmod 755 "$out/bin/$tool"
  # Into a file first: a pipe into head can fail the writer under pipefail.
  "$out/bin/$tool" --version >"$out/.version.txt" 2>&1
  echo "build: $tool -> $(sed -n 1p "$out/.version.txt")"
  rm -f "$out/.version.txt"
done
