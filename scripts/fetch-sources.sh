#!/usr/bin/env bash
# Downloads the source distribution (sdist) of every GPL-licensed distribution
# named in upstream.json .gpl_sources, at the exact version the locks install,
# and verifies each against the sha256 PyPI publishes for it. These sdists are
# the corresponding source each GitHub release carries (GPL-3.0 section 6).
# Every platform lock must install the same version of each of them.
#
#   scripts/fetch-sources.sh <outdir>
#
# Result: <outdir>/<sdist file name>, one per GPL distribution.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
out=${1:?usage: fetch-sources.sh <outdir>}
mkdir -p "$out"

norm() { tr '[:upper:]_.' '[:lower:]--' <<<"$1"; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

for dist in $(jq -r '.gpl_sources[]' "$manifest"); do
  want=$(norm "$dist")
  versions=$(cat "$root"/locks/*.txt | grep -E '^[^#]' | while read -r req _; do
    name=${req%%==*}
    [ "$(norm "$name")" = "$want" ] && printf '%s\n' "${req#*==}"
  done | sort -u)
  [ "$(printf '%s\n' "$versions" | grep -c .)" = 1 ] ||
    { echo "fetch-sources: the locks install '${versions//$'\n'/ }' of $dist, expected exactly one version" >&2; exit 1; }
  json=$(curl -fsSL --retry 3 "https://pypi.org/pypi/$dist/$versions/json")
  url=$(jq -er 'first(.urls[] | select(.packagetype == "sdist")) | .url' <<<"$json")
  digest=$(jq -er 'first(.urls[] | select(.packagetype == "sdist")) | .digests.sha256' <<<"$json")
  file="$out/$(basename "$url")"
  curl -fsSL --retry 3 --retry-delay 5 -o "$file" "$url"
  actual=$(sha256 "$file")
  if [ "$actual" != "$digest" ]; then
    echo "fetch-sources: sha256 mismatch for $(basename "$url"): PyPI says $digest, got $actual" >&2
    rm -f "$file"; exit 1
  fi
  echo "fetch-sources: $(basename "$url") sha256 $actual OK (PyPI)"
done
