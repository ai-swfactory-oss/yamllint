#!/usr/bin/env bash
# Downloads the python-build-standalone CPython pinned in upstream.json for one
# platform and verifies it against its pinned sha256 digest: the
# install_only_stripped archive (the interpreter we ship) and the matching
# "full" archive, which is used only for its licenses/ directory (the licence
# texts of the libraries CPython bundles: OpenSSL, libffi, sqlite, zlib, ...).
# An archive whose digest does not match is deleted and the script exits 1, so
# nothing unverified is extracted, installed into or published. A digest that
# is not sha256:<64 hex> is refused before anything is downloaded.
#
#   scripts/fetch-python.sh <outdir> <platform>
#
# UPSTREAM_JSON overrides the manifest; UPSTREAM_BASE_URL overrides the release
# download URL (the tests point it at local files).
#
# Result: <outdir>/python/...                               (the interpreter)
#         <outdir>/LICENSES/python-build-standalone/...     (bundled-library licences)
#         <outdir>/LICENSES/cpython/LICENSE.txt
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
out=${1:?usage: fetch-python.sh <outdir> <platform>}
platform=${2:?usage: fetch-python.sh <outdir> <platform>}
build=$(jq -er .python.build "$manifest")
base=${UPSTREAM_BASE_URL:-https://github.com/astral-sh/python-build-standalone/releases/download/$build}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

fetch() { # <kind> -> path of the verified archive
  local kind=$1 name digest file actual
  name=$(jq -er --arg p "$platform" --arg k "$kind" '.python.assets[$p][$k].name' "$manifest")
  digest=$(jq -er --arg p "$platform" --arg k "$kind" '.python.assets[$p][$k].digest' "$manifest")
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "fetch-python: $platform $kind: digest '$digest' is not sha256:<64 hex>" >&2; exit 1; }
  file="$out/.downloads/$name"
  mkdir -p "$out/.downloads"
  echo "fetch-python: $platform $kind <- $base/${name//+/%2B}" >&2
  curl -fsSL --retry 3 --retry-delay 5 -o "$file" "$base/${name//+/%2B}"
  actual=$(sha256 "$file")
  if [ "sha256:$actual" != "$digest" ]; then
    echo "fetch-python: $platform: sha256 mismatch for $name" >&2
    echo "  expected ${digest#sha256:}" >&2
    echo "  actual   $actual" >&2
    rm -rf "$out/.downloads"
    exit 1
  fi
  echo "fetch-python: $platform $kind sha256 $actual OK" >&2
  printf '%s\n' "$file"
}

install=$(fetch install)
full=$(fetch full)

rm -rf "$out/python" "$out/LICENSES/python-build-standalone" "$out/LICENSES/cpython"
mkdir -p "$out/LICENSES/python-build-standalone" "$out/LICENSES/cpython"
tar -xzf "$install" -C "$out"
test -x "$out/python/bin/python3" || { echo "fetch-python: no python/bin/python3 in the install archive" >&2; exit 1; }

lic=$(mktemp -d)
# Decompress to a file, then extract from it. Piping zstd into a tar asked for
# one member fails under pipefail whenever tar exits once it has that member
# and zstd hits the closed pipe.
zstd -d -q -o "$lic/full.tar" "$full"
tar -xf "$lic/full.tar" -C "$lic" python/licenses
cp -R "$lic/python/licenses/." "$out/LICENSES/python-build-standalone/"
rm -rf "$lic"
test -n "$(ls -A "$out/LICENSES/python-build-standalone")" || { echo "fetch-python: no licences in the full archive" >&2; exit 1; }
cp "$out/python/lib/python3."*/LICENSE.txt "$out/LICENSES/cpython/LICENSE.txt"

rm -rf "$out/.downloads"
