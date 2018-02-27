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

You are strongly encouraged to update the version numbers in accordance with the [semver standard](http://semver.org/):
* Use `tag(pkg, :major)` when you make *backwards-incompatible* API changes (i.e. changes that will break existing user code).
* Use `tag(pkg, :minor)` when you *add functionality* in a backwards-compatible way (i.e. existing user code will still work, but code using the *new* functionality will not work with *older* versions of your package).
* Use `tag(pkg, :patch)` when you make bug fixes and other improvements that *don't change the API* (i.e. user code is unchanged).
The key question is not how "small" the change is, but how it affects the API and user code.  (Don't be reluctant to bump the minor version when you add new features to the API, no matter how trivial — version numbers are cheap!)

If you drop support for an older version of Julia, you should make at least a minor version bump even if there were no API changes.

### publish()
For each new package version tagged in `METADATA` not already published, make sure that the tagged package commits have been pushed to the repository at the registered URL for the package and if they all have, open a pull request to `METADATA`.

### generate(pkg, license)
Generate a new package named `pkg` with one of the bundled license: `"MIT"`, `"BSD"`, `CC0`, `"ISC"`, `"ASL"`, `"MPL"`, `"GPL-2.0+"`, `"GPL-3.0+"`, `"LGPL-2.1+"`, `"LGPL-3.0+"`. If you want to make a package with a different license, you can edit it afterwards. Generate creates a git repository at `Pkg.dir(pkg)` for the package and inside it `LICENSE.md`, `README.md`, `REQUIRE`, the julia entrypoint `$pkg/src/$pkg.jl`, and Travis and AppVeyor CI configuration files `.travis.yml` and `appveyor.yml`.

> *Warning*: If you release code for Package X under the GPL, you may discourage collaboration from members of the Julia community who work on non-GPL packages. For example, if a user works on Package Y, which is licensed under the MIT license that is used in many community projects, other developers might not feel safe to read the code you contribute to Package Y because any indication that their work is derivative could lead to litigation. In effect, you create a situation in which your source code is percieved as being closed to anyone who is working on a non-GPL project.

Keyword parameters:

* `path` - a location where the package will be generated, the default location is `Pkg.dir()`
* `travis` - enables generation of the `.travis.yml` configuration for [Travis CI](https://travis-ci.org/) service, the default value is `true`.
* `appveyor` - enables generation of the `appveyor.yml` configuration for [Appveyor](http://www.appveyor.com/) service, the default value is `true`.
* `coverage` - enables generation of a code coverage reporting to [Coveralls](https://coveralls.io) and [Codecov](https://codecov.io) services, default value is `true`.

### license([lic])
List all bundled licenses. If a license label specified as a parameter then a full text of the license will be printed.

### freeable([io])
Returns a list of packages which are good candidates for
`Pkg.free`. These are packages for which you are not tracking the
tagged release, but for which a tagged release is equivalent to the
current version. You can use `Pkg.free(PkgDev.freeable())` to
automatically free all such packages.

This also prints (to `io`, defaulting to standard output) a list of
packages that are ahead of a tagged release, and prints the number of
commits that separate them. It can help discover packages that may be
due for tagging.
