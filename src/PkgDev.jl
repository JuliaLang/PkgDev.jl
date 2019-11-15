module PkgDev

using Pkg, LibGit2, Registrator, URIParser
import GitHub
import PkgButlerEngine

include("utils.jl")
# include("github.jl")
# include("entry.jl")
include("license.jl")
# include("generate.jl")
include("tag.jl")

# remove extension .jl
const PKGEXT = ".jl"
splitjl(pkg::AbstractString) = endswith(pkg, PKGEXT) ? pkg[1:end-length(PKGEXT)] : pkg

"""
    dir(pkg, [paths...])

Return package `pkg` directory location through search. Additional `paths` are appended.
"""
function dir(pkg::AbstractString)
    pkg = splitjl(pkg)
    if isdefined(Base, :find_in_path)
        pkgsrc = Base.find_in_path(pkg, Pkg.dir())
    else
        pkgsrc = Base.find_package(pkg)
    end
    pkgsrc === nothing && return ""
    abspath(dirname(pkgsrc), "..") |> realpath
end
dir(pkg::AbstractString, args...) = normpath(dir(pkg),args...)

# """
#     generate(pkg,license)

# Generate a new package named `pkg` with one of these license keys:  `"MIT"`, `"BSD"`,
# `"ASL"`, `"MPL"`, `"GPL-2.0+"`, `"GPL-3.0+"`,  `"LGPL-2.1+"`, `"LGPL-3.0+"`. If you want to
# make a package with a  different license, you can edit it afterwards.

# Generate creates a git repo at `Pkg.dir(pkg)` for the package and  inside it `LICENSE.md`,
# `README.md`, `REQUIRE`, and the julia  entrypoint `$pkg/src/$pkg.jl`. Travis, AppVeyor CI
# configuration files `.travis.yml` and `appveyor.yml` with code coverage statistics using
# Coveralls or Codecov are created by default, but each can be disabled  individually by
# setting `travis`, `appveyor` or `coverage` to `false`.
# """
# generate(pkg::AbstractString, license::AbstractString;
#          force::Bool=false, authors::Union{AbstractString,Array} = [],
#          config::Dict=Dict(), path::AbstractString = Pkg.Dir.path(),
#          travis::Bool = true, appveyor::Bool = true, coverage::Bool = true) =
#     Generate.package(splitjl(pkg), license, force=force, authors=authors, config=config, path=path,
#                      travis=travis, appveyor=appveyor, coverage=coverage)

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
            username = LibGit2.prompt("Enter user name", default=username)
            LibGit2.set!(cfg, "user.name", username)
        else
            println("User name: $username")
        end

        useremail = LibGit2.get(cfg, "user.email", "")
        if isempty(useremail) || force
            useremail = LibGit2.prompt("Enter user email", default=useremail)
            LibGit2.set!(cfg, "user.email", useremail)
        else
            println("User email: $useremail")
        end

        # setup github account
        ghuser = LibGit2.get(cfg, "github.user", "")
        if isempty(ghuser) || force
            ghuser = LibGit2.prompt("Enter GitHub user", default=(isempty(ghuser) ? username : ghuser))
            LibGit2.set!(cfg, "github.user", ghuser)
        else
            println("GitHub user: $ghuser")
        end
    finally
        finalize(cfg)
    end
    lowercase(LibGit2.prompt("Do you want to change this configuration?", default="N")) == "y" && config(true)
    return
end

end # module
