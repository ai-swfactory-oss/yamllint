/** The yamllint version this package runs, without any -r.N re-pack suffix. */
export declare const upstreamVersion: string;

/** The `<os>-<cpu>` platforms a package is published for. */
export declare const supportedPlatforms: readonly string[];

/** No yamllint package is published for this os and cpu. */
export declare class UnsupportedPlatformError extends Error {
  readonly name: 'UnsupportedPlatformError';
  readonly platform: string;
  readonly arch: string;
}

/** A package is published for this os and cpu, but it is not installed. */
export declare class PlatformPackageMissingError extends Error {
  readonly name: 'PlatformPackageMissingError';
  readonly platform: string;
  readonly arch: string;
  readonly packageName: string;
}

/** Name of the platform package for this os and cpu (default: this process's). */
export declare function platformPackage(platform?: string, arch?: string): string;

/**
 * Absolute path of the yamllint executable for this os and cpu (default: this process's): a stub running yamllint on
 * the bundled CPython, isolated from the host Python.
 */
export declare function binaryPath(platform?: string, arch?: string): string;
