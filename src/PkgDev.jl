module PkgDev

using Pkg, LibGit2, RegistryTools, URIs
import GitHub
using UUIDs
using FilePathsBase
import TOML

include("tag.jl")

# The URL forms git accepts for a remote:
#   https://github.com/owner/repo(.git)
#   ssh://git@github.com/owner/repo(.git)
#   git@github.com:owner/repo(.git)            (scp-like syntax, no scheme)
# The conditional `(?(<protocol>)...)` separates the two spellings: with a
# scheme the host is followed by '/', without one by ':'.
const GIT_URL_REGEX = r"^(?:(?<protocol>[A-Za-z][A-Za-z0-9+.\-]*)://)?(?:[\w.+\-]+(?::[^@/]*)?@)?(?<host>[^/:]+)(?(<protocol>)(?::\d+)?/|[:/])(?<path>.+?)/*$"

"""
    parse_git_url(url)

Split a git remote `url` into its `protocol`, its `host` and its `path` (the
`owner/repo` part, with any `.git` suffix removed). Handles https URLs, `ssh://`
URLs and the scp-like `git@host:owner/repo` syntax.
"""
function parse_git_url(url::AbstractString)
    m = match(GIT_URL_REGEX, url)
    m===nothing && error("Cannot parse the git URL $url.")

    path = String(m[:path])

    # Drop a trailing '.git', whatever its casing.
    if lowercase(splitext(path)[2])==".git"
        path = splitext(path)[1]
    end

    # A URL with no path at all mis-parses as scp-like syntax, leaving the
    # scheme's slashes in the path; reject that rather than pass it on.
    (isempty(path) || startswith(path, '/') || occursin("//", path)) && error("Cannot parse the git URL $url.")

    return (
        protocol = m[:protocol]===nothing ? nothing : String(m[:protocol]),
        host = String(m[:host]),
        path = path
    )
end

"""
    get_repo_onwer_from_url(pkg_url)

Return the `owner/repo` part of the GitHub remote `pkg_url`.
"""
function get_repo_onwer_from_url(pkg_url)
    parsed = parse_git_url(pkg_url)

    count(==('/'), parsed.path)==1 || error("Expected a GitHub URL of the form owner/repo, got $pkg_url.")

    return parsed.path
end

"""
    https_url_from_git_url(url)

Return the https spelling of the git remote `url`.

URLs that already use http(s) are returned unchanged: this is the URL that ends
up in a registry's `Package.toml`, and rewriting it (by appending a `.git`
suffix, say) for a package that is already registered would look like an attempt
to change the registered repository URL.
"""
function https_url_from_git_url(url::AbstractString)
    parsed = parse_git_url(url)

    parsed.protocol!==nothing && lowercase(parsed.protocol) in ("http", "https") && return String(url)

    return "https://$(parsed.host)/$(parsed.path).git"
end

"""
    uses_ssh_transport(url)

Whether the git remote `url` talks ssh rather than http(s).
"""
function uses_ssh_transport(url::AbstractString)
    protocol = parse_git_url(url).protocol

    # No scheme means the scp-like syntax, which is always ssh.
    return protocol===nothing || lowercase(protocol) in ("ssh", "git+ssh")
end

"""
    ssh_url_from_repo(host, owner_repo_name)

Return the scp-like ssh URL for `owner_repo_name` on `host`. Built by hand
rather than taken from the GitHub API, whose `ssh_url` GitHub.jl parses into a
`URI` that does not round-trip back to this form.
"""
ssh_url_from_repo(host::AbstractString, owner_repo_name::AbstractString) = "git@$host:$owner_repo_name.git"

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
