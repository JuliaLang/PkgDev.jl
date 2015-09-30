# Julia Package Development Kit (PDK)

[![Build Status](https://travis-ci.org/JuliaLang/PkgDev.jl.svg?branch=master)](https://travis-ci.org/JuliaLang/PkgDev.jl)


Julia PDK provides a set of tools for a developer to create, maintain and register packages in Julia package repository, a.k.a. [METADATA](https://github.com/JuliaLang/METADATA.jl).

## Usage

### register(pkg, [url])
Register `pkg` at the git URL `url`, defaulting to the configured origin URL of the git repo `Pkg.dir(pkg)`.

### tag(pkg, [ver, [commit]])
Tag `commit` as version `ver` of package `pkg` and create a version entry in `METADATA`. If not provided, `commit` defaults to the current commit of the `pkg` repo. If `ver` is one of the symbols `:patch`, `:minor`, `:major` the next patch, minor or major version is used. If `ver` is not provided, it defaults to `:patch`.

### publish()
For each new package version tagged in `METADATA` not already published, make sure that the tagged package commits have been pushed to the repo at the registered URL for the package and if they all have, open a pull request to `METADATA`.

### generate(pkg,license)
Generate a new package named `pkg` with one of these license keys: `"MIT"`, `"BSD"` or `"ASL"`. If you want to make a package with a different license, you can edit it afterwards. Generate creates a git repo at `Pkg.dir(pkg)` for the package and inside it `LICENSE.md`, `README.md`, `REQUIRE`, the julia entrypoint `$pkg/src/$pkg.jl`, and Travis and AppVeyor CI configuration files `.travis.yml` and `appveyor.yml`.
