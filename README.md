# yamllint

[![update](https://github.com/ai-swfactory-oss/yamllint/actions/workflows/update.yml/badge.svg)](https://github.com/ai-swfactory-oss/yamllint/actions/workflows/update.yml)
[![build](https://github.com/ai-swfactory-oss/yamllint/actions/workflows/build.yml/badge.svg)](https://github.com/ai-swfactory-oss/yamllint/actions/workflows/build.yml)

[yamllint](https://github.com/adrienverge/yamllint) as npm packages, with no Python needed on the host.
- Each platform package carries a pinned [python-build-standalone](https://github.com/astral-sh/python-build-standalone) CPython, with yamllint and its dependencies installed from hash-locked wheels.
- The tree is built on that platform's own runner, updated automatically, and published to GitHub Packages.
- There is no download at install time and there are no install scripts.

| Package | What |
|---|---|
| `@ai-swfactory-oss/yamllint` | Thin: the `yamllint` bin, and `binaryPath()` / `upstreamVersion` for Node. Depends optionally on the four platform packages, pinned exactly. |
| `@ai-swfactory-oss/yamllint-<darwin\|linux>-<arm64\|x64>` | `bin/yamllint` (a stub), `python/` (CPython 3.13 with the locked distributions), `LICENSES/` |

## Install and use

GitHub Packages needs the scope line in your project's `.npmrc` (`@ai-swfactory-oss:registry=https://npm.pkg.github.com`) and a `read:packages` token in your user `~/.npmrc`; see the [shfmt wrapper](https://github.com/ai-swfactory-oss/shfmt#install). Then:

```sh
npm install --save-dev @ai-swfactory-oss/yamllint
npx yamllint --version
```

```js
const { spawnSync } = require('node:child_process');
const { binaryPath } = require('@ai-swfactory-oss/yamllint');
spawnSync(binaryPath(), ['-f', 'parsable', '.'], { stdio: 'inherit' });
```

`binaryPath()` returns `bin/yamllint` in the platform package. That is a POSIX `sh` stub running `python/bin/python3 -I -m yamllint`. `-I` (isolated mode) ignores `PYTHONPATH`, `PYTHONHOME`, the user site-packages and the current directory, so nothing on the host can change what runs.

## What is pinned, and how it is checked

- **Interpreter.** `upstream.json` pins, per platform:
  - the `install_only_stripped` archive (what we ship);
  - the matching `full` archive, used only for its `licenses/` directory.

  Both digests come from GitHub and are cross-checked against the release's `SHA256SUMS`. `scripts/fetch-python.sh` refuses any archive whose sha256 differs.
- **Distributions.** `locks/<platform>.txt` lists every installed distribution with one sha256, the one PyPI publishes for that platform's wheel.
  - The install runs `pip install --require-hashes --only-binary=:all: --no-deps`, so every file is checked, nothing is compiled, and nothing unlocked is installed. `pip check` then proves the lock is complete.
  - The `lock` workflow verifies every hash against PyPI on each pull request. It regenerates a lock marked `PENDING` on that platform's runner: it downloads each resolved file, hashes it, and requires the hash to equal the index's.
- **Provenance.** Every published tarball has a GitHub build-provenance attestation.

## Corresponding source (GPL-3.0-or-later)

Every GitHub release `v<version>` carries:
- the yamllint sdist exactly as published on PyPI (verified against PyPI's sha256);
- `build-scripts.tar.gz`: the manifest, locks, scripts and workflows.

Each package's `NOTICE` names that release. The other bundled components are permissive and GPL-compatible, and their licence texts are in `LICENSES/`: CPython (PSF-2.0), its bundled libraries (OpenSSL Apache-2.0 and others), PyYAML (MIT), and pathspec (MPL-2.0, shipped as source).

**Releases are never deleted while their package version is served.**

## Versions

- The package version equals the yamllint version.
- A rebuild without a yamllint change (a new CPython build or a dependency re-lock) is `<version>-r.<n>`, published with dist-tag `latest`.

## Workflows

| Workflow | When | What |
|---|---|---|
| `update` | Daily; monthly keepalive | Follows yamllint on PyPI and the latest python-build-standalone build on CPython 3.13. Rewrites `upstream.json` and marks the locks `PENDING`, then opens a pull request that `lock` re-locks and `build` tests. Re-runs a missing publish. |
| `lock` | Pull requests touching `upstream.json` or `locks/`; called by `update` | Verifies the locks against PyPI, or regenerates `PENDING` ones on each platform. |
| `build` | Push to `main` touching the build inputs; manual; called by `update` | Named digest/lock test; GPL sdists; build each platform tree on its runner; stage; launcher tests; pack once; smoke-test the packed tarballs on four runners. On push or manual publish it attests, publishes, and creates the release with the source. |
| `pr` | Every pull request | `build` without publishing. |
| `failures` | After `update`/`build` on `main` | Keeps one `build-failure` issue in sync. |

## License

- The scripts and workflows in this repository are **MIT** (see [`LICENSE`](LICENSE)).
- The **npm packages are GPL-3.0-or-later**, the licence of yamllint.

This project is not affiliated with the yamllint project or the Python Software Foundation.
