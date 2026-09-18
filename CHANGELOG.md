# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The GitHub token can now be supplied through the `GITHUB_TOKEN` environment
  variable, in addition to the existing `credentials` keyword argument and the git
  credential manager. All three are now documented in the README ([#170]).

### Fixed

- A credential the GitHub API rejects now produces an error that says so and names
  the ways to supply a personal access token, rather than an opaque HTTP error.
  This is what happens when the git credential manager stores a password instead
  of a token ([#158]).
- An unset `github.user` git setting is no longer an error: the username is asked
  of GitHub instead.
- `PkgDev.tag` no longer insists on a fork of the registry: if you can push to the
  registry itself, which is the case when you own it, the registration branch now
  goes there directly and the pull request is opened from it ([#185]). Owning a
  repository and having a fork of it are mutually exclusive on GitHub, so a
  personal registry could not be tagged into at all before.
- The pull request against the registry is now opened against the registry's
  default branch instead of always against `master`.
- Tagging into General no longer enumerates every fork of
  `JuliaRegistries/General` (thousands of repositories, paged 30 at a time) to
  compute a value it then discards.
- `PkgDev.tag` now works for packages whose `origin` remote uses ssh, both the
  `git@github.com:owner/repo.git` and the `ssh://git@github.com/owner/repo.git`
  spelling ([#188]). The https URL is what gets registered, and the registration
  branch is pushed over ssh too, so no https credentials are needed for git.
- The remote URL is now parsed before the release branch is created, so an
  unsupported URL fails before any commit is made rather than after the release
  branch has already been pushed.

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

[#158]: https://github.com/JuliaLang/PkgDev.jl/issues/158
[#170]: https://github.com/JuliaLang/PkgDev.jl/issues/170
[#185]: https://github.com/JuliaLang/PkgDev.jl/issues/185
[#188]: https://github.com/JuliaLang/PkgDev.jl/issues/188
