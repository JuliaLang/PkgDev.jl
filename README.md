# Julia Package Development Kit (PDK)

[![Build Status](https://travis-ci.org/JuliaLang/PkgDev.jl.svg?branch=master)](https://travis-ci.org/JuliaLang/PkgDev.jl)[![Build status](https://ci.appveyor.com/api/projects/status/gnd6dqbdaxcx1c23/branch/master?svg=true)](https://ci.appveyor.com/project/wildart/pkgdev-jl/branch/master)

PkgDev.jl provides a set of tools for a developer to create, maintain and register packages in a Julia package registry, for example (but not limited to) [METADATA](https://github.com/JuliaLang/METADATA.jl).

## Requirements

For closer integration with GitHub API, PkgDev.jl requires `curl` to be installed.

## Usage

### register(pkgdir, registry, [url])
Register or tag the package at `pkgdir` at the git URL `url` to the registry at `registry`, defaulting to the configured origin URL of the git repository at `pkgdir`.
The version used is the `version` entry in the package's project file (typically `Project.toml`).


Tag the current commit as version `ver` of package `pkg` and create a version entry in `METADATA`.

You are strongly encouraged to update the version numbers in accordance with the [semver standard](http://semver.org/):

If your version is above 1.0 use the following scheme for bumping version numbers:

1. **major tag** when you make *backwards-incompatible* API changes (i.e. changes that will break existing user code).
2. **minor tag** when you *add functionality* in a backwards-compatible way (i.e. existing user code will still work, but code using the *new* functionality will not work with *older* versions of your package).
3. **patch tag** when you make bug fixes and other improvements that *don't change the API* (i.e. user code is unchanged).

If your version is below 1.0, use minor tags for case 1 and patch tags for both case 2 and 3.

The key question is not how "small" the change is, but how it affects the API and user code.  (Don't be reluctant to bump the minor version when you add new features to the API, no matter how trivial — version numbers are cheap!)

If you drop support for an older version of Julia, you should make at least a minor version bump even if there were no API changes.

### publish(registry)

For each new package version tagged in `METADATA` not already published, make sure that the tagged package commits have been pushed to the repository at the registered URL for the package and if they all have, open a pull request to `METADATA`.

### generate(pkgdir, license)

Generate a new package named `pkg` with one of the bundled license: `"MIT"`, `"BSD"`, `CC0`, `"ISC"`, `"ASL"`, `"MPL"`, `"GPL-2.0+"`, `"GPL-3.0+"`, `"LGPL-2.1+"`, `"LGPL-3.0+"`. If you want to make a package with a different license, you can edit it afterwards. Generate creates a git repository at `Pkg.dir(pkg)` for the package and inside it `LICENSE.md`, `README.md`, `REQUIRE`, the julia entrypoint `$pkg/src/$pkg.jl`, and Travis and AppVeyor CI configuration files `.travis.yml` and `appveyor.yml`.

> *Warning*: If you release code for Package X under the GPL, you may discourage collaboration from members of the Julia community who work on non-GPL packages. For example, if a user works on Package Y, which is licensed under the MIT license that is used in many community projects, other developers might not feel safe to read the code you contribute to Package Y because any indication that their work is derivative could lead to litigation. In effect, you create a situation in which your source code is percieved as being closed to anyone who is working on a non-GPL project.

Keyword parameters:

* `travis` - enables generation of the `.travis.yml` configuration for [Travis CI](https://travis-ci.org/) service, the default value is `true`.
* `appveyor` - enables generation of the `appveyor.yml` configuration for [Appveyor](http://www.appveyor.com/) service, the default value is `true`.
* `coverage` - enables generation of a code coverage reporting to [Codecov](https://codecov.io) services, default value is `true`.

### license([lic])

List all bundled licenses. If a license label specified as a parameter then a full text of the license will be printed.
