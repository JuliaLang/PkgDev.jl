# PkgDev

## Overview

PkgDev provides tools for Julia package developers. The package is currently being rewritten for Julia 1.x and only for brave early adopters.

## Usage

### PkgDev.tag(package_name, version=nothing; registry=nothing, release_notes=nothing)

Tag a new release for package `package_name`. The package you want to tag must be deved in the current Julia environment. You pass the package name `package_name` as a `String`. The git commit that is the `HEAD` in the package folder will form the basis for the version to be tagged.

If you don't specify a `version`, then the `version` field in the `Project.toml` _must_ have the format `x.y.z-DEV`, and the command will tag version `x.y.z` as the next release. Alternatively you can specify one of `:major`, `:minor` or `:patch` for the `version` parameter. In that case `PkgDev.tag` will increase that part of the version number by 1 and tag that version. Finally, you can also specify a full `VersionNumber` as the value for the `version` parameter, in which case that version will be tagged.

The only situation where you would specify a value for `registry` is when you want to register a new package for the first time in a registry that is not `General`. In all other situations, `PkgDev.tag` will automatically figure out in which registry your package is registered. When you do pass a value for `registry`, it should simply be the short name of a registry that is one of the registries your local system is connected with.

Both https and ssh remotes are supported for the package repository: the
`origin` remote may be `https://github.com/owner/repo.git`,
`git@github.com:owner/repo.git` or `ssh://git@github.com/owner/repo.git`. Note
that a GitHub API token is required in all cases, since `PkgDev.tag` opens pull
requests on your behalf. The package and its registry must be hosted on GitHub.

If you want to add custom release notes for [TagBot](https://github.com/JuliaRegistries/TagBot), do so with the `release_notes` keyword.

`PkgDev.tag` runs through the following process when it tags a new version:
1. Create a new release branch called `release-x.y.z`.
2. Change the version field in `Project.toml` and commit that change on the release branch.
3. Change the version field in `Project.toml` to `x.y.z+1-DEV` and commit that change also to the release branch.
4a. For packages in the General registry: add a comment that triggers [Registrator](https://github.com/JuliaRegistries/Registrator.jl).
4b. For packages in other registries: Open a pull request against the registry that tags the first new commit on the release branch as a new version `x.y.z`.
5. Open a pull request against the package repository to merge the release branch into `master`.

If you have [TagBot](https://github.com/JuliaRegistries/TagBot) installed for your package with the `branches: true` setting, it will automatically merge the `release-x.y.z` branch into `master` once the pull request for the registry has been merged.
