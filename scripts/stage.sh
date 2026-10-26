#!/usr/bin/env bash
# Single-quoted jq programs and Markdown backticks are literal on purpose.
# shellcheck disable=SC2016
# Renders the npm packages from the per-platform trees.
#
#   scripts/stage.sh <builddir> <outdir>
#
# <builddir>/<platform>/{bin,python,LICENSES} are the outputs of
# scripts/build.sh, one per platform in upstream.json.
# Result: <outdir>/<package>            the launcher
#         <outdir>/<package>-<platform> one self-contained package per platform
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
built=${1:?usage: stage.sh <builddir> <outdir>}
out=${2:?usage: stage.sh <builddir> <outdir>}

pkg=$(jq -er .package "$manifest")
scope=@ai-swfactory-oss
repo_url="https://github.com/ai-swfactory-oss/$pkg.git"
version=$(bash "$root/scripts/pkgver.sh")
license=$(jq -er .license "$manifest")
license_dist=$(jq -er .license_dist "$manifest")
python=$(jq -er '"CPython \(.python.version) (python-build-standalone \(.python.build))"' "$manifest")
release="https://github.com/ai-swfactory-oss/$pkg/releases/tag/v$version"
read -r -a platforms <<<"$(jq -r '.python.assets | keys | join(" ")' "$manifest")"

common='{
  license: $license,
  author: "ai-swfactory",
  homepage: "https://github.com/ai-swfactory-oss/\($pkg)#readme",
  bugs: { url: "https://github.com/ai-swfactory-oss/\($pkg)/issues" },
  repository: { type: "git", url: $repo },
  publishConfig: { registry: "https://npm.pkg.github.com" }
}'

notice() { # <package name> <platform or ""> <line>
  cat "$root/packages/NOTICE.in"
  printf '\nThis package: %s %s.\n%s\n' "$1" "$version" "$3"
  if [ -n "$2" ]; then
    printf '\nContents: %s, unmodified, with these distributions installed from\n' "$python"
    printf 'the wheels PyPI publishes, each verified against the sha256 in locks/%s.txt:\n\n' "$2"
    grep -E '^[^#]' "$root/locks/$2.txt" | sed -E 's/ --hash=/  /; s/^/  /'
    printf '\nLicence texts of each distribution, of CPython and of the libraries CPython\n'
    printf 'bundles are in LICENSES/.\n'
  fi
  printf '\nCorresponding source of the GPL-licensed distributions (section 6(d) of\n'
  printf 'the GPL-3.0): the GitHub release\n  %s\n' "$release"
  printf 'carries their source distributions (sdists, as published on PyPI) and\n'
  printf 'build-scripts.tar.gz (the manifest, locks, scripts and workflows that built\n'
  printf 'this package).\n'
}

rm -rf "$out"
mkdir -p "$out"

optional='{}'
for platform in "${platforms[@]}"; do
  os=${platform%%-*}
  cpu=${platform#*-}
  name="$scope/$pkg-$platform"
  dir="$out/$pkg-$platform"
  mkdir -p "$dir"
  cp -R "$built/$platform/bin" "$built/$platform/python" "$built/$platform/LICENSES" "$dir/"
  # sed -n 1p reads all its input, so sort never writes to a closed pipe.
  first=$(find "$dir/LICENSES/$license_dist" -type f | sort | sed -n 1p)
  test -n "$first" || { echo "stage: no licence file for $license_dist" >&2; exit 1; }
  cp "$first" "$dir/LICENSE"
  notice "$name" "$platform" "Platform: $os-$cpu." >"$dir/NOTICE"
  {
    printf '# %s\n\n' "$name"
    printf 'The `%s` tools for `%s` / `%s`, on a bundled %s.\n\n' "$pkg" "$os" "$cpu" "$python"
    printf 'Do not install this package directly: install [`%s/%s`](https://github.com/ai-swfactory-oss/%s), which depends on it optionally and runs it.\n\n' "$scope" "$pkg" "$pkg"
    printf 'Provenance: `gh attestation verify` against `ai-swfactory-oss/%s` for the tarball.\n\n' "$pkg"
    printf 'License: %s (see `LICENSE`, `LICENSES/` and `NOTICE`). The corresponding source is attached to %s.\n' "$license" "$release"
  } >"$dir/README.md"

  jq -n --arg name "$name" --arg version "$version" --arg pkg "$pkg" --arg python "$python" \
    --arg os "$os" --arg cpu "$cpu" --arg repo "$repo_url" --arg license "$license" \
    "{
      name: \$name,
      version: \$version,
      description: \"\(\$pkg) on a bundled \(\$python) for \(\$os)-\(\$cpu) (used by @ai-swfactory-oss/\(\$pkg))\",
      keywords: [\$pkg, \"python\"],
      os: [\$os],
      cpu: [\$cpu],
      files: [\"bin/\", \"python/\", \"LICENSES/\", \"LICENSE\", \"NOTICE\", \"README.md\"],
      preferUnplugged: true
    } + $common" >"$dir/package.json"

  optional=$(jq -c --arg n "$name" --arg v "$version" '. + {($n): $v}' <<<"$optional")
done

launcher="$out/$pkg"
mkdir -p "$launcher"
cp -R "$root/packages/$pkg/." "$launcher/"
cp "$out/$pkg-${platforms[0]}/LICENSE" "$launcher/LICENSE"
notice "$scope/$pkg" "" "This package holds no interpreter or tool: it runs the ones from $scope/$pkg-<platform>-<arch>." >"$launcher/NOTICE"
jq --arg version "$version" --arg repo "$repo_url" --arg license "$license" --arg pkg "$pkg" \
  --argjson optional "$optional" --argjson tools "$(jq -c '.tools | keys' "$manifest")" \
  ". + {version: \$version, optionalDependencies: \$optional, tools: \$tools} + $common" \
  "$root/packages/$pkg/package.json" >"$launcher/package.json"
find "$launcher/bin" -name '*.js' -exec chmod 755 {} +

echo "stage: $version -> $out"
ls -1 "$out"
