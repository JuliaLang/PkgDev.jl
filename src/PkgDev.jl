__precompile__()

module PkgDev

using Compat
import Compat.String

export Entry, Generate, GitHub

include("utils.jl")
include("github.jl")
include("entry.jl")
include("license.jl")
include("generate.jl")

const cd = Pkg.Dir.cd

"""
    dir(pkg, [paths...])

Returns package `pkg` directory location through search. Additional `paths` are appended.
"""
function dir(pkg::AbstractString)
    pkgsrc = Base.find_in_path(bytestring(pkg), Pkg.dir())
    pkgsrc === nothing && return ""
    abspath(dirname(pkgsrc), "..") |> realpath
end
dir(pkg::AbstractString, args...) = normpath(dir(pkg),args...)

"""
    register(pkg, [url])

Register `pkg` at the git URL `url`, defaulting to the configured origin URL of the git repo `Pkg.dir(pkg)`.
"""
register(pkg::AbstractString) = Entry.register(pkg)
register(pkg::AbstractString, url::AbstractString) = Entry.register(pkg,url)

"""
    tag(pkg, [ver, [commit]])

Tag `commit` as version `ver` of package `pkg` and create a version entry in `METADATA`. If not provided, `commit` defaults to the current commit of the `pkg` repo. If `ver` is one of the symbols `:patch`, `:minor`, `:major` the next patch, minor or major version is used. If `ver` is not provided, it defaults to `:patch`.
"""
tag(pkg::AbstractString, sym::Symbol=:patch) = cd(Entry.tag,pkg,sym)
tag(pkg::AbstractString, sym::Symbol, commit::AbstractString) = cd(Entry.tag,pkg,sym,false,commit)

tag(pkg::AbstractString, ver::VersionNumber; force::Bool=false) = cd(Entry.tag,pkg,ver,force)
tag(pkg::AbstractString, ver::VersionNumber, commit::AbstractString; force::Bool=false) =
    cd(Entry.tag,pkg,ver,force,commit)

submit(pkg::AbstractString) = cd(Entry.submit, pkg)
submit(pkg::AbstractString, commit::AbstractString) = cd(Entry.submit,pkg,commit)

"""
    publish()

For each new package version tagged in `METADATA` not already published, make sure that the tagged package commits have been pushed to the repo at the registered URL for the package and if they all have, open a pull request to `METADATA`.

A branch in user's remote fork of `METADATA` repository will be created that can be used to create pull request to `METADATA` package registry.
Optionally, function accepts a name for a pull request branch. If it isn't provided name will be automatically generated.
"""
publish(prbranch::AbstractString="") = Entry.publish(Pkg.Dir.getmetabranch(), prbranch)

doc"""
    generate(pkg,license)

Generate a new package named `pkg` with one of these license keys: `"MIT"`, `"BSD"`, `"ASL"` or `"MPL"`. If you want to make a package with a different license, you can edit it afterwards. Generate creates a git repo at `Pkg.dir(pkg)` for the package and inside it `LICENSE.md`, `README.md`, `REQUIRE`, and the julia entrypoint `$pkg/src/$pkg.jl`. Travis, AppVeyor CI configuration files `.travis.yml` and `appveyor.yml` with code coverage statistics using Coveralls or Codecov are created by default, but each can be disabled individually by setting `travis`, `appveyor` or `coverage` to `false`.
"""
generate(pkg::AbstractString, license::AbstractString;
         force::Bool=false, authors::Union{AbstractString,Array} = [],
         config::Dict=Dict(), path::AbstractString = Pkg.Dir.path(),
         travis::Bool = true, appveyor::Bool = true, coverage::Bool = true) =
    Generate.package(pkg, license, force=force, authors=authors, config=config, path=path,
                     travis=travis, appveyor=appveyor, coverage=coverage)

"""
    config()
Interactive configuration of the development environment.

PDK operations require `git` minimum configuration that keeps user signature (user.name & user.email).
"""
function config(force::Bool=false)
    # setup global git configuration
    cfg = LibGit2.GitConfig(LibGit2.Consts.CONFIG_LEVEL_GLOBAL)
    try
        println("Julia PDK configuration:")

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

"""
    freeable([io::IO=STDOUT])

Returns a list of packages which are good candidates for
`Pkg.free`. These are packages for which you are not tracking the
tagged release, but for which a tagged release is equivalent to the
current version. You can use `Pkg.free(PkgDev.freeable())` to
automatically free all such packages.

This also prints (to `io`, defaulting to standard output) a list of
packages that are ahead of a tagged release, and prints the number of
commits that separate them. It can help discover packages that may be
due for tagging.
"""
freeable(args...) = cd(Entry.freeable, args...)

function __init__()
    # Check if git configuration exists
    cfg = LibGit2.GitConfig(LibGit2.Consts.CONFIG_LEVEL_GLOBAL)
    try
        username = LibGit2.get(cfg, "user.name", "")
        if isempty(username)
            warn("Julia PDK is not configured. Please, run `PkgDev.config()` before performing any operations.")
        end
    finally
        finalize(cfg)
    end
end

end # module
