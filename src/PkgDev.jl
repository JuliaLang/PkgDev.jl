module PkgDev

using Pkg, LibGit2, RegistryTools, URIParser
import GitHub
import PkgButlerEngine
import Base64

include("tag.jl")
include("pkgbutler.jl")

# remove extension .jl
const PKGEXT = ".jl"
splitjl(pkg::AbstractString) = endswith(pkg, PKGEXT) ? pkg[1:end-length(PKGEXT)] : pkg

function get_repo_onwer_from_url(pkg_url)
    startswith(pkg_url, "git@") &&  error("Only packages that use https as the git transport protocol are supported.")

    pkg_owner_repo_name = if lowercase(splitext(URI(pkg_url).path)[2])==".git"
        splitext(URI(pkg_url).path)[1][2:end]
    else
        URI(pkg_url).path[2:end]
    end

    return pkg_owner_repo_name
end

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
