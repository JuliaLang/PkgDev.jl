# Julia Package Development Kit (PDK)

[![Build Status](https://travis-ci.org/JuliaLang/PkgDev.jl.svg?branch=master)](https://travis-ci.org/JuliaLang/PkgDev.jl)[![Build status](https://ci.appveyor.com/api/projects/status/gnd6dqbdaxcx1c23/branch/master?svg=true)](https://ci.appveyor.com/project/wildart/pkgdev-jl/branch/master)

PkgDev.jl provides a set of tools for a developer to create, maintain and register packages in Julia package repository, a.k.a. [METADATA](https://github.com/JuliaLang/METADATA.jl).

## Requirements
For closer integration with GitHub API, PkgDev.jl requires `curl` to be installed.

## Usage

### register(pkg, [url])
Register `pkg` at the git URL `url`, defaulting to the configured origin URL of the git repository `Pkg.dir(pkg)`.

### tag(pkg, [ver, [commit]])
Tag `commit` as version `ver` of package `pkg` and create a version entry in `METADATA`. If not provided, `commit` defaults to the current commit of the `pkg` repository. If `ver` is one of the symbols `:patch`, `:minor`, `:major` the next patch, minor or major version is used. If `ver` is not provided, it defaults to `:patch`.

### publish()
For each new package version tagged in `METADATA` not already published, make sure that the tagged package commits have been pushed to the repository at the registered URL for the package and if they all have, open a pull request to `METADATA`.

### generate(pkg, license)
Generate a new package named `pkg` with one of the bundled license: `"MIT"`, `"BSD"`, `"ASL"` or `"MPL"`. If you want to make a package with a different license, you can edit it afterwards. Generate creates a git repository at `Pkg.dir(pkg)` for the package and inside it `LICENSE.md`, `README.md`, `REQUIRE`, the julia entrypoint `$pkg/src/$pkg.jl`, and Travis and AppVeyor CI configuration files `.travis.yml` and `appveyor.yml`.

Keyword parameters:

* `path` - a location where the package will be generated, the default location is `Pkg.dir()`
* `travis` - enables generation of the `.travis.yml` configuration for [Travis CI](https://travis-ci.org/) service, the default value is `true`.
* `appveyor` - enables generation of the `appveyor.yml` configuration for [Appveyor](http://www.appveyor.com/) service, the default value is `true`.
* `coverage` - enables generation of a code coverage reporting to [Coveralls](https://coveralls.io) and [Codecov](https://codecov.io) services, default value is `true`.

### license([lic])
List all bundled licenses. If a license label specified as a parameter then a full text of the license will be printed.
