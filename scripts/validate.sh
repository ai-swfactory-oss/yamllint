#!/usr/bin/env bash
# The repository's validate command (.panoptic.json "validate": "bash scripts/validate.sh"),
# run by `claude-factory work commit` on the gate host. Fast, and offline but
# for one step: the network-bound and per-platform checks (lock, fetch, build,
# smoke) stay in CI. The one network step installs the published, exactly
# pinned @ai-swfactory-oss/yamllint to check the workflows' YAML syntax,
# because this validate builds no runnable yamllint of its own (coordinator
# ruling, 2026-10-26).
# The same file serves the yamllint and ansible repositories (it reads
# upstream.json .package).
#
#   1. shellcheck over every shell script; then no script, test or workflow
#      may pipe into a reader that can exit before its input ends (head,
#      grep -q, a quitting sed, tar): under pipefail the writer then fails on
#      the closed pipe, at random. A fixture holding each form must be
#      flagged first; then a YAML syntax check of every workflow in
#      .github/workflows with the packaged yamllint (installed into a scratch
#      prefix, never globally), after a known-bad fixture fails it;
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

echo "== no pipe into an early-exiting reader"
# Write the producer's output to a file first, then read the file.
# A single bar (not ||), then the reader.
early_exit='(^|[^|])\|[[:space:]]*(head|tar|grep[[:space:]]+(-[A-Za-z]*q|--quiet)|sed[[:space:]][^|]*[0-9$/]q)([[:space:]]|$)'
# The fixture spells the bar through a variable so this file does not match.
bar='|'
printf '%s\n' "a $bar head -n1" "b $bar grep -q x" "c $bar grep -Eq x" "d $bar sed 1q" "e $bar tar -xf - m" >"$work/pipes-bad.sh"
grep -cE "$early_exit" "$work/pipes-bad.sh" >"$work/pipes-bad.count" || true
[ "$(cat "$work/pipes-bad.count")" = 5 ] || { echo "validate: the pipe check missed a fixture form" >&2; exit 1; }
# Comment lines are prose, not commands.
if grep -nE "$early_exit" scripts/*.sh test/*.sh .github/workflows/*.yml | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' >"$work/pipes.txt"; then
  cat "$work/pipes.txt"; echo "validate: a pipe ends in a reader that can exit early; write to a file first" >&2; exit 1
fi
echo "pipes: no early-exiting reader"

echo "== workflow YAML syntax (packaged yamllint; the one network step)"
yamllint_version=1.38.0
mkdir -p "$work/yamllint"
printf '{"name":"validate-yamllint","version":"1.0.0","private":true}\n' >"$work/yamllint/package.json"
# The scope's registry line comes from this repository's .npmrc; the token,
# if any, stays in the user's own ~/.npmrc.
cp .npmrc "$work/yamllint/.npmrc"
npm install --prefix "$work/yamllint" --no-save --no-audit --no-fund \
  "@ai-swfactory-oss/yamllint@$yamllint_version" >"$work/yamllint-install.log" 2>&1 ||
  { cat "$work/yamllint-install.log"; echo "validate: could not install @ai-swfactory-oss/yamllint@$yamllint_version" >&2; exit 1; }
yamllint="$work/yamllint/node_modules/.bin/yamllint"
[ -x "$yamllint" ] || { echo "validate: $yamllint is missing after install" >&2; exit 1; }
# Syntax only: no style rules, so only a document YAML cannot parse fails.
syntax_only='{rules: {}}'
printf 'jobs:\n  a:\n    steps:\n      - name: bad (linux: colon)\n' >"$work/bad-workflow.yml"
if "$yamllint" -d "$syntax_only" "$work/bad-workflow.yml" >"$work/bad-workflow.txt" 2>&1; then
  cat "$work/bad-workflow.txt"; echo "validate: yamllint accepted a workflow YAML cannot parse" >&2; exit 1
fi
cat "$work/bad-workflow.txt"
"$yamllint" -d "$syntax_only" .github/workflows/*.yml
echo "workflows: YAML syntax OK"

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
