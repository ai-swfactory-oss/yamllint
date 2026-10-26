#!/usr/bin/env bash
# Named test: scripts/fetch-python.sh, which every build runs before it
# installs anything, refuses an interpreter archive or licence archive whose
# sha256 does not match its pin (deleting it, extracting nothing) and an
# unpinned digest (downloading nothing), and accepts the same archives with
# their true digests, so the check is not vacuous. scripts/build.sh refuses a
# lock that is not a complete hash lock before it fetches anything. Runs
# offline: the "release" is local fixture archives.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

mkdir -p "$work/tree/python/bin" "$work/tree/python/lib/python3.13" "$work/full/python/licenses" "$work/release"
printf '#!/bin/sh\necho fake python\n' >"$work/tree/python/bin/python3"
chmod 755 "$work/tree/python/bin/python3"
printf 'PSF licence\n' >"$work/tree/python/lib/python3.13/LICENSE.txt"
printf 'OpenSSL licence\n' >"$work/full/python/licenses/LICENSE.openssl.txt"
install=cpython-9.9.9+1-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz
full=cpython-9.9.9+1-x86_64-unknown-linux-gnu-pgo+lto-full.tar.zst
tar -czf "$work/release/$install" -C "$work/tree" python
tar -cf - -C "$work/full" python | zstd -q -o "$work/release/$full"
# fetch-python.sh URL-encodes "+" as %2B; a file:// URL decodes it back.
install_digest=sha256:$(sha256 "$work/release/$install")
full_digest=sha256:$(sha256 "$work/release/$full")
wrong=sha256:$(printf '%064d' 0)

manifest() { # <install digest> <full digest>
  jq -n --arg i "$install" --arg id "$1" --arg f "$full" --arg fd "$2" \
    '{python: {version: "9.9.9", build: "1", assets: {"linux-x64": {install: {name: $i, digest: $id}, full: {name: $f, digest: $fd}}}}}'
}

fetch() { # <manifest> <outdir> <log>
  set +e
  UPSTREAM_JSON=$1 UPSTREAM_BASE_URL="file://$work/release" bash "$root/scripts/fetch-python.sh" "$2" linux-x64 >"$3" 2>&1
  local rc=$?
  set -e
  cat "$3"
  return "$rc"
}

expect_refusal() { # <case> <pattern>
  if fetch "$work/$1.json" "$work/out-$1" "$work/$1.log"; then
    echo "digest-mismatch: $1: fetch accepted it" >&2; exit 1
  fi
  grep -q "$2" "$work/$1.log" || { echo "digest-mismatch: $1: the failure does not say '$2'" >&2; exit 1; }
  test ! -e "$work/out-$1/python" || { echo "digest-mismatch: $1: something was extracted" >&2; exit 1; }
  test -z "$(ls -A "$work/out-$1/.downloads" 2>/dev/null)" || { echo "digest-mismatch: $1: a download was left behind" >&2; exit 1; }
}

manifest "$wrong" "$full_digest" >"$work/install.json"
expect_refusal install "sha256 mismatch for $install"

manifest "$install_digest" "$wrong" >"$work/full.json"
expect_refusal full "sha256 mismatch for $full"

manifest "sha256:PENDING" "$full_digest" >"$work/pending.json"
expect_refusal pending 'is not sha256:<64 hex>'

manifest "$install_digest" "$full_digest" >"$work/true.json"
fetch "$work/true.json" "$work/out-true" "$work/true.log"
test -x "$work/out-true/python/bin/python3"
test -f "$work/out-true/LICENSES/python-build-standalone/LICENSE.openssl.txt"
test -f "$work/out-true/LICENSES/cpython/LICENSE.txt"

mkdir -p "$work/locks"
printf '# PENDING: regenerate with the lock workflow\n' >"$work/locks/linux-x64.txt"
set +e
UPSTREAM_JSON="$work/true.json" UPSTREAM_BASE_URL="file://$work/release" LOCK_DIR="$work/locks" \
  bash "$root/scripts/build.sh" "$work/out-lock" linux-x64 >"$work/lock.log" 2>&1
rc=$?
set -e
cat "$work/lock.log"
test "$rc" -ne 0 || { echo "digest-mismatch: build accepted an incomplete lock" >&2; exit 1; }
grep -q 'is not a complete hash lock' "$work/lock.log" || { echo "digest-mismatch: the lock refusal is not named" >&2; exit 1; }
test ! -e "$work/out-lock/python" || { echo "digest-mismatch: build fetched before checking the lock" >&2; exit 1; }

echo "digest-mismatch: OK"
