# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- Removed the Julia Package Butler integration: `PkgDev.enable_pkgbutler`,
  `PkgDev.switch_pkgbutler_channel` and `PkgDev.switch_pkgbutler_template` are gone,
  along with the `PkgButlerEngine` dependency.
- Removed code formatting support: `PkgDev.format` is gone, along with the
  `DocumentFormat` dependency.
- Removed the unused `JSON` and `Base64` dependencies.
- Removed the Package Butler GitHub Actions workflows and the stale Travis CI
  configuration from the repository. The only remaining functionality of the
  package is tagging releases via `PkgDev.tag`.

### Changed

- The minimum supported Julia version is now 1.10 (was 1.6).
