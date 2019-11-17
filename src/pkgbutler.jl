function enable_pkgbutler(package_name::AbstractString; channel=:auto, force::Bool=false)
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

        pkg_owner_repo_name = get_repo_onwer_from_url(pkg_url)
    finally
        close(pkg_repo)
    end

    configure_deploykey(pkg_owner_repo_name, force)

    PkgButlerEngine.configure_pkg(pkg_path; channel=channel)

    return
end

import GitHub.DEFAULT_API

mutable struct DeployKey <: GitHub.GitHubType
    id::Union{Int, Nothing}
    key::Union{String, Nothing}
    url::Union{GitHub.HTTP.URI, Nothing}
    title::Union{String, Nothing}
    verified::Union{Bool, Nothing}
    created_at::Union{GitHub.Dates.DateTime, Nothing}
    read_only::Union{Bool, Nothing}
end

DeployKey(data::Dict) = GitHub.json2github(DeployKey, data)

GitHub.namefield(key::DeployKey) = key.id

GitHub.@api_default function deploykey(api::GitHub.GitHubAPI, repo, deploykey_obj; options...)
    result = GitHub.gh_get_json(api, "/repos/$(GitHub.name(repo))/keys/$(GitHub.name(deploykey_obj))"; options...)
    return DeployKey(result)
end

GitHub.@api_default function deploykeys(api::GitHub.GitHubAPI, repo; options...)
    results, page_data = GitHub.gh_get_paged_json(api, "/repos/$(GitHub.name(repo))/keys"; options...)
    return map(DeployKey, results), page_data
end

GitHub.@api_default function create_deploykey(api::GitHub.GitHubAPI, repo; options...)
    result = GitHub.gh_post_json(api, "/repos/$(GitHub.name(repo))/keys"; options...)
    return DeployKey(result)
end

GitHub.@api_default function delete_deploykey(api::GitHub.GitHubAPI, repo, item; options...)
    return GitHub.gh_delete(api, "/repos/$(GitHub.name(repo))/keys/$(GitHub.name(item))"; options...)
end

function configure_deploykey(repo, force)
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

    existing_deploykeys = PkgDev.deploykeys(repo, auth=myauth)

    existing_pkgbutler_deploykeys_indices = findall(i->i.title=="Julia Package Butler", existing_deploykeys[1])

    if !force && length(existing_pkgbutler_deploykeys_indices) > 0
        println("Found one or more existing deployment keys on Github for $repo that are named 'Julia Package Butler'. Should these be deleted? (yes/no)")
        answer = readline()
        if !(answer=="" || lowercase(answer)=="yes" || lowercase(answer)=="y")
            empty!(existing_pkgbutler_deploykeys_indices)
        end
    end

    for dk in existing_pkgbutler_deploykeys_indices
        delete_deploykey(repo, existing_deploykeys[1][dk], auth=myauth)
    end

    create_deploykey(repo, params=Dict("title"=>"Julia Package Butler", "key"=>pub_deploykey, "read_only"=>false), auth=myauth)

    println()
    println("Add the following text as a GitHub Actions Secret with the name JLPKGBUTLER_TOKEN:")
    println()
    println(Base64.base64encode(private_deploykey))
    println()
    println("Add the repository upload token you find at the following URL as a GitHub Actions Secret with the name CODECOV_TOKEN:")
    println()
    println("https://codecov.io/gh/$repo/settings")
end
