# Julia Package Manifest File

This document describes a Julia package manifest file. The manifest file uses the TOML format.

## Fields
Example of the package manifest

```toml
[package]
julia   = "0.4"                       # specifies least supported version
license = "MIT"                       # explicit license designation
authors = ["John Dow <john@dow.org>"] # list of authors
build = "src/build-native.jl"         # path to build script
description = "small text description to facilitate text search."
repository = "https://github.com/testproject/Project.jl"
documentation = "http://docs.github.io/Project.jl"
tests   = ["test/first.jl"]           # List of test files

[dependencies]
Codecs = "*"                          # registered package
Colors = "0.3.4"                      # registered package with version
"github.com/julia/Example.jl" = "*"   # unregistered package
"github.com/julia/Example.jl" = "0.1" # unregistered package with version

[dev-dependencies]                    # deps used for in tests and benchmarks
FactCheck = "*"                       # registered package required for development
Coverage  = "0.1.1"                   # registered package with version

[dev-dependencies.Coverage]           # package subsection of `dev-dependencies`
exclude = "src/somefile.jl"           # some development option
```

### [package]

Following fields are mandatory in this section:

- `license`, an explicit license designation. Type: string.

- `authors`, list of package authors (includes email address). Type: string array.

- `tests`, list of test files. Type: string array.

Following fields are optional in this section:

- `julia`, least supported version. Type: string.

- `build`, a file in the repository which is a build script for building native code. Type: string.

- `description`, provides small text description. Type: string.

- `repository`, url to the package main repository (supports schemes `https` and `file`). Type: string.

- `documentation`, url to the package documentation. Type: string.

- `keywords`, list of keywords to support package discovery. Type: string array.

- `homepage`, url to the project homepage. Type: string.


**Package version** is derived from repository tags which are appropriately formatted.

### [dependencies]
This section contains list of the package dependencies.

### [dev-dependencies]

This section contains testing, coverage and benchmark specific options. This section my contain subsections related to a particular dependency package. The subsection should be have an appropriate package name suffix, e.g. `[dev-dependencies.Coverage]`.

## Package Manager

Create an installation repository directory in `JULIA_PKGDIR`, e.g. `installed`. A designated installation repository allows lock-free modifications of the repository state (all conflicts are handled by file system) and keeps a history of operations if they duplicated in git repository. The installation repository should support multiple Julia versions.

### Installation of the package
- Copy a package manifest file of an installed package into the installation repository from METADATA
- Read `dependencies` section of the package manifest file and install missing packages
    - registered dependencies
        - resolved with METADATA and add to the package repository
        - native code is built using build script from `build` field
    - unregistered dependencies
        - inform user about installation of an unregistered package
        - cloned into the package repository along with registered packages if does not exists
        - dependencies resolved using the package manifest file
        - no building of native code

### Uninstallation of the package
- Read `dependencies` section of the package manifest file
    - registered dependencies
        - resolved with METADATA and inform to user dependencies that cannot be removed due to conflicts
        - remove non-conflicting dependencies
    - unregistered dependencies
        - remove from the package repository
- Remove manifest file from the installation repository directory


### GitHub related info
- *Currently:* GitHub 2FA tokens reside in `.github` folded which is located in a version directory of `JULIA_PKGDIR`. This creates unnecessary duplication of tokens when switching between versions.
- *Proposal:* Move `.github` folder to `JULIA_PKGDIR`.

## Q & A

- Do we allow a registration of a package with unregistered dependencies?
    *No*
- Why TOML format and not JSON or any other?
    *Using TOML will allow to read certain sections of the manifest file, i.e. `dependencies`, without a complete implementation of a parser.*


## Links
- https://github.com/JuliaLang/julia/issues/11955
- https://wiki.python.org/moin/Distutils/Tutorial
- https://docs.npmjs.com/files/package.json
- https://msdn.microsoft.com/en-us/library/windows/apps/br211473.aspx
- https://docs.oracle.com/javase/8/docs/technotes/guides/jar/jar.html#Manifest_Specification
- http://conda.pydata.org/docs/building/meta-yaml.html#the-meta-yaml-file
- http://doc.crates.io/manifest.html
- https://www.debian.org/doc/debian-policy/index.html
