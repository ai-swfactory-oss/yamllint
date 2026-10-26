#!/usr/bin/env bash
# The repository's validate command (.panoptic.json "validate": "bash scripts/validate.sh"),
# run by `claude-factory work commit` on the gate host. Offline and fast: the
# network-bound and per-platform checks (lock, fetch, build, smoke) stay in CI.
# The same file serves the yamllint and ansible repositories (it reads
# upstream.json .package).
#
#   1. shellcheck over every shell script;
#   2. named test test/digest-mismatch.sh (an interpreter or licence archive
#      with a wrong or unpinned digest is refused; an incomplete lock is refused
#      by scripts/build.sh before anything is fetched);
#   3. every lock is either a complete hash lock or exactly "# PENDING" (no
#      half-edited lock reaches main);
#   4. named tests test/launcher.test.js over a launcher staged by
#      scripts/stage.sh from fixture per-platform trees.
#
# Needs bash, jq, tar, gzip, zstd, curl, node and shellcheck on the gate host.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
# The gate reports only the exit status; keep the full output for diagnosis.
mkdir -p build
exec > >(tee build/validate.log) 2>&1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pkg=$(jq -er .package upstream.json)
license_dist=$(jq -er .license_dist upstream.json)

echo "== shellcheck"
shellcheck scripts/*.sh test/*.sh

echo "== named test: digest mismatch and incomplete lock"
bash test/digest-mismatch.sh

echo "== locks"
for lock in locks/*.txt; do
  if grep -q PENDING "$lock"; then
    [ "$(grep -vc '^#' "$lock")" = 0 ] || { echo "validate: $lock mixes PENDING with entries" >&2; exit 1; }
    echo "$lock: PENDING (lock.yml regenerates it)"
  else
    grep -vE '^(#|[a-z0-9-]+(\.[a-z0-9-]+)*==[^ ]+ --hash=sha256:[0-9a-f]{64}$)' "$lock" && {
      echo "validate: $lock has lines that are not 'name==version --hash=sha256:<64 hex>'" >&2; exit 1; }
    echo "$lock: complete"
  fi
done

echo "== named tests: launcher (staged from fixture trees)"
for platform in $(jq -r '.python.assets | keys | join(" ")' upstream.json); do
  tree="$work/built/$platform"
  mkdir -p "$tree/bin" "$tree/python/bin" "$tree/LICENSES/$license_dist"
  for tool in $(jq -r '.tools | keys[]' upstream.json); do
    printf '#!/bin/sh\necho fixture\n' >"$tree/bin/$tool"
    chmod 755 "$tree/bin/$tool"
  done
  printf 'GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\n(fixture)\n' >"$tree/LICENSES/$license_dist/LICENSE"
done
bash scripts/stage.sh "$work/built" "$work/npm" >/dev/null
LAUNCHER_DIR="$work/npm/$pkg" node --test test/launcher.test.js

echo "validate: OK"
