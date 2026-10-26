# @ai-swfactory-oss/yamllint

[yamllint](https://github.com/adrienverge/yamllint) with its own Python. The matching platform package carries a pinned CPython 3.13 with yamllint and its dependencies installed from hash-locked wheels. No Python is needed on the host, nothing is downloaded at install time, and there are no install scripts.

Platforms: `linux-x64`, `linux-arm64`, `darwin-x64`, `darwin-arm64`.

```sh
npm install --save-dev @ai-swfactory-oss/yamllint   # scope @ai-swfactory-oss -> https://npm.pkg.github.com
npx yamllint --version
```

```js
const { binaryPath, upstreamVersion } = require('@ai-swfactory-oss/yamllint');
// binaryPath(): the yamllint stub for this os and cpu (runs the bundled CPython with -I, isolated from the host Python)
// upstreamVersion: the yamllint version, e.g. "1.38.0"
```

`binaryPath()` throws `UnsupportedPlatformError` or `PlatformPackageMissingError` (for example after `--omit=optional`).

License: GPL-3.0-or-later. The corresponding source (the yamllint sdist and the build scripts) is attached to the GitHub release of each version. The licences of the bundled components are in the platform package's `LICENSES/`. Details: https://github.com/ai-swfactory-oss/yamllint#corresponding-source-gpl-30-or-later
