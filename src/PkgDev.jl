__precompile__()

module PkgDev

using LibGit2
import Pkg

struct PkgDevError
    msg::String
end

Base.show(io::IO, err::PkgDevError) = print(io, err.msg)

# remove extension .jl
splitjl(pkg::AbstractString) = endswith(pkg, ".jl") ? pkg[1:end-3] : pkg

include("utils.jl")
include("github.jl")
include("Registry.jl")
include("license.jl")
include("generate.jl")

add_project(pkgdir::String) = Generate.create_project_from_require(pkgdir)

defaut_reg = joinpath(Pkg.depots1(), "registries", "General")

"""
    register(pkgdir; [commit, registry, url])

Register package at `pkgdir` at `commit` into the registry at `registry`. If
not provided, `commit` defaults to the current commit of the `pkg` repo,
`registry` defaults to the General registry and `url` defaults to the url of the
`origin` remote.
"""
register(pkgdir::AbstractString; commit=nothing, registry=default_reg(), url=nothing ) =
    Registry.register(registry, pkgdir; commit=commit, url=url)

"""
    tag(pkgdir; [commit, registry])

Tag `commit` of package at `pkgdir` into the registry at `registry`. If
not provided, `commit` defaults to the current commit of the `pkg` repo
and `registry` defaults to the General registry.
"""
tag(pkgdir::AbstractString; commit = nothing, registry=default_reg()) =
    Registry.tag(registry, pkgdir; commit=commit)


#=
"""
    publish()

For each new package version tagged in `METADATA` not already  published, make sure that the
tagged package commits have been pushed  to the repo at the registered URL for the package
and if they all  have, open a pull request to `METADATA`.

A branch in user's remote fork of `METADATA` repository will be  created that can be used to
create pull request to `METADATA` package  registry.

Optionally, function accepts a name for a pull request branch. If it  isn't provided name
will be automatically generated.
"""
publish(prbranch::AbstractString="") = Entry.publish(Pkg.Dir.getmetabranch(), prbranch)
=#

@doc raw"""
    generate(pkgdir, license)

Generate a new package named `pkg` with one of these license keys:  `"MIT"`, `"BSD"`,
`"ASL"`, `"MPL"`, `"GPL-2.0+"`, `"GPL-3.0+"`,  `"LGPL-2.1+"`, `"LGPL-3.0+"`. If you want to
make a package with a  different license, you can edit it afterwards.

Generate creates a git repo at `pkgdir` for the package and inside it `LICENSE.md`,
`README.md`, `Project.toml`, and the julia entrypoint `$pkg/src/$pkg.jl`. Travis, AppVeyor CI
configuration files `.travis.yml` and `appveyor.yml` with code coverage statistics using
Codecov is created by default, but each can be disabled individually by
setting `travis`, `appveyor` or `coverage` to `false`.
"""
generate(pkg::AbstractString, license::AbstractString;
         force::Bool=false, authors::Union{AbstractString,Array} = [],
         config::Dict=Dict(), travis::Bool = true, appveyor::Bool = true,
         coverage::Bool = true) =
    Generate.package(splitjl(pkg), license, force=force, authors=authors, config=config,
                     travis=travis, appveyor=appveyor, coverage=coverage)

"""
    config()

Interactive configuration of the development environment.

PkgDev.jl operations require `git` minimum configuration that keeps user signature
(user.name & user.email).
"""
function config(force::Bool=false)
    # setup global git configuration
    cfg = LibGit2.GitConfig(LibGit2.Consts.CONFIG_LEVEL_GLOBAL)
    try
        println("PkgDev.jl configuration:")

        username = LibGit2.get(cfg, "user.name", "")
        if isempty(username) || force
            username = Base.prompt("Enter user name", default=username)
            LibGit2.set!(cfg, "user.name", username)
        else
            println("User name: $username")
        end

        useremail = LibGit2.get(cfg, "user.email", "")
        if isempty(useremail) || force
            useremail = Base.prompt("Enter user email", default=useremail)
            LibGit2.set!(cfg, "user.email", useremail)
        else
            println("User email: $useremail")
        end

        # setup github account
        ghuser = LibGit2.get(cfg, "github.user", "")
        if isempty(ghuser) || force
            ghuser = Base.prompt("Enter GitHub user", default=(isempty(ghuser) ? username : ghuser))
            LibGit2.set!(cfg, "github.user", ghuser)
        else
            println("GitHub user: $ghuser")
        end
    finally
        finalize(cfg)
    end
    lowercase(Base.prompt("Do you want to change this configuration?", default="N")) == "y" && config(true)
    return
end

function __init__()
    # Check if git configuration exists
    cfg = LibGit2.GitConfig(LibGit2.Consts.CONFIG_LEVEL_GLOBAL)
    try
        username = LibGit2.get(cfg, "user.name", "")
        if isempty(username)
            @warn("PkgDev.jl is not configured. Please, run `PkgDev.config()` " *
                  "before performing any operations.")
        end
    finally
        finalize(cfg)
    end
end

end # module
