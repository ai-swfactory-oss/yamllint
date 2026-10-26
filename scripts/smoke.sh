#!/usr/bin/env bash
# The single-quoted node programs are literal on purpose.
# shellcheck disable=SC2016
# Named test, per platform: installs the packed tarballs into a scratch project,
# as a consumer would, and checks that binaryPath() resolves to the yamllint
# stub, that it reports upstreamVersion, lints a fixture with one known
# violation, runs only the bundled interpreter (a hostile PYTHONPATH and a
# hostile module in the cwd change nothing), and that the package carries its
# licences and points at the corresponding source.
#
#   scripts/smoke.sh <tgzdir> <platform>      e.g. dist/tgz linux-x64
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tgz=$(cd "${1:?usage: smoke.sh <tgzdir> <platform>}" && pwd)
platform=${2:?usage: smoke.sh <tgzdir> <platform>}
upstream=$(jq -er .version "$root/upstream.json")
version=$(bash "$root/scripts/pkgver.sh")

launcher="$tgz/ai-swfactory-oss-yamllint-$version.tgz"
native="$tgz/ai-swfactory-oss-yamllint-$platform-$version.tgz"

for f in "$launcher" "$native"; do
  test -f "$f" || { echo "smoke: missing $f" >&2; exit 1; }
  if tar -xzOf "$f" package/package.json | jq -e '.scripts // {} | keys | any(test("install"))' >/dev/null; then
    echo "smoke: $f declares an install script" >&2; exit 1
  fi
  tar -xzOf "$f" package/NOTICE | grep -q 'Corresponding source' || { echo "smoke: $f NOTICE does not point at the corresponding source" >&2; exit 1; }
done
tar -tzf "$native" | grep -q '^package/LICENSES/python-build-standalone/' || { echo "smoke: no bundled-library licences" >&2; exit 1; }
tar -tzf "$native" | grep -q '^package/LICENSES/yamllint/' || { echo "smoke: no yamllint licence" >&2; exit 1; }

work=$(mktemp -d)
cd "$work" || exit 1
printf '{"name":"smoke","version":"1.0.0","private":true}\n' >package.json
npm install --no-audit --no-fund "$launcher" "$native"

echo "== binaryPath(), upstreamVersion and --version"
node -e '
  const { execFileSync } = require("node:child_process");
  const fs = require("node:fs");
  const yamllint = require("@ai-swfactory-oss/yamllint");
  const [expected] = process.argv.slice(1);
  if (yamllint.upstreamVersion !== expected) throw new Error(`upstreamVersion ${yamllint.upstreamVersion} != ${expected}`);
  const bin = yamllint.binaryPath();
  fs.accessSync(bin, fs.constants.X_OK);
  const printed = execFileSync(bin, ["--version"], { encoding: "utf8" }).trim();
  if (printed !== `yamllint ${expected}`) throw new Error(`${bin} --version printed ${printed}`);
  console.log(bin, printed);
' "$upstream"
bin=$(node -p 'require("@ai-swfactory-oss/yamllint").binaryPath()')

echo "== lint: one known violation"
printf 'key: value   \n' >bad.yaml
set +e
"$bin" -d '{rules: {trailing-spaces: enable}}' -f parsable bad.yaml >lint.txt
rc=$?
set -e
cat lint.txt
[ "$rc" = 1 ] || { echo "smoke: yamllint exited $rc on a violation, expected 1" >&2; exit 1; }
grep -q 'trailing-spaces' lint.txt || { echo "smoke: the violation does not name trailing-spaces" >&2; exit 1; }
printf 'key: value\n' >good.yaml
"$bin" -d '{rules: {trailing-spaces: enable}}' good.yaml

echo "== isolation from the host Python"
mkdir -p hostile/yamllint
printf 'raise SystemExit("hostile yamllint imported")\n' >hostile/yamllint/__init__.py
cp -R hostile/yamllint ./yamllint
PYTHONPATH="$work/hostile" PYTHONHOME=/nonexistent PYTHONSTARTUP=/nonexistent "$bin" --version
rm -rf ./yamllint

echo "== the interpreter is the bundled one"
prefix=$(dirname "$(dirname "$bin")")/python
got=$("$prefix/bin/python3" -I -c 'import sys; print(sys.prefix)')
[ "$(cd "$got" && pwd -P)" = "$(cd "$prefix" && pwd -P)" ] || { echo "smoke: sys.prefix $got is not $prefix" >&2; exit 1; }

echo "smoke: $platform OK"
