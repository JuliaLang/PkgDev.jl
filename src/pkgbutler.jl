function enable_pkgbutler(package_name::AbstractString; channel=:auto)
    ctx = Pkg.Types.Context()
    haskey(ctx.env.project.deps, package_name) || error("Unkonwn package $package_name.")
    pkg_uuid = ctx.env.project.deps[package_name]
    pkg_path = ctx.env.manifest[pkg_uuid].path
    pkg_path===nothing && error("Package must be deved to enable the Julia Package Butler.")

    pkg_owner_repo_name = nothing

    pkg_repo = GitRepo(pkg_path)
    try
        pkg_remote = LibGit2.lookup_remote(pkg_repo, "origin")

        pkg_remote===nothing && error("The package must have a remote called origin.")

        pkg_url = LibGit2.url(pkg_remote)

        pkg_owner_repo_name = splitext(URI(pkg_url).path)[1][2:end]
    finally
        close(pkg_repo)
    end

    configure_deploykey(pkg_owner_repo_name)

    PkgButlerEngine.configure_pkg(pkg_path; channel=channel)

    return
end

import GitHub.DEFAULT_API

GitHub.@api_default function add_deploy_key(api::GitHub.GitHubAPI, repo; options...)
    result = GitHub.gh_post_json(api, "/repos/$(GitHub.name(repo))/keys"; options...)
    return result
end

function configure_deploykey(repo)
    pub_deploykey, private_deploykey = mktempdir() do f
        p = joinpath(f, "deploykey")
        run(`ssh-keygen -q -t rsa -f $p -N ''`)

        pub_deploykey = read("$p.pub", String)
        private_deploykey = read(p, String)

        rm(p, force=true)
        rm("$p.pub", force=true)

        return pub_deploykey, private_deploykey
    end

    creds = LibGit2.GitCredential(GitConfig(), "https://github.com")

    # TODO Check for creds===nothing if there are no credentials stored
    myauth = GitHub.authenticate(read(creds.password, String))
    Base.shred!(creds.password)

    add_deploy_key(repo, params=Dict("title"=>"Julia Package Butler", "key"=>pub_deploykey, "read_only"=>false), auth=myauth)

    println()
    println("Add the following text as a GitHub Actions Secret with the name DOCUMENTER_KEY:")
    println()
    println(Base64.base64encode(private_deploykey))
    println()
    println("Add the following text as a GitHub Actions Secret with the name JLPKGBUTLER_TOKEN")
    println()
    println(private_deploykey)
end
