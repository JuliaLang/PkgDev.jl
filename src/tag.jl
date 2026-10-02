function TOML_print_conversion(x)
    x isa VersionNumber && return "$x"
    error("TOML unhandled type $(typeof(x)).")
end

function tag(
        package_name::AbstractString,
        version::Union{Symbol,VersionNumber,Nothing}=nothing;
        kwargs...
        )

    ctx = Pkg.Types.Context()
    haskey(ctx.env.project.deps, package_name) || error("Unknown package $package_name.")
    pkg_uuid = ctx.env.project.deps[package_name]
    pkg_path = ctx.env.manifest[pkg_uuid].path
    pkg_path===nothing && error("Package must be deved to be tagged.")

    tag_internal(package_name, pkg_uuid, pkg_path, version; kwargs...)
end

function tag(
        package_path::AbstractPath,
        version::Union{Symbol,VersionNumber,Nothing}=nothing;
        kwargs...)

    project_toml = isfile(joinpath(package_path, "Project.toml")) ? joinpath(package_path, "Project.toml") : isfile(joinpath(package_path, "JuliaProject.toml")) ? joinpath(package_path, "JuliaProject.toml") : nothing
    project_toml === nothing && error("Could not find a 'Project.toml' at $package_path.")    

    project_content = TOML.parsefile(string(project_toml))

    package_name = get(project_content, "name", nothing)
    package_name===nothing && error("The project toml for the package doesn't contain a name.")

    pkg_uuid = get(project_content, "uuid", nothing)
    pkg_uuid===nothing && error("The project toml for the package doesn't contain a uuid.")

    tag_internal(package_name, pkg_uuid, string(package_path), version; kwargs...)
end

# This is adapted over from LocalRegistry.jl
function our_collect_registries()
    registries = []
    for depot in Pkg.depots()
        isdir(depot) || continue
        reg_dir = joinpath(depot, "registries")
        isdir(reg_dir) || continue
        for name in readdir(reg_dir)
            file = joinpath(reg_dir, name, "Registry.toml")
            if !isfile(file)
                # Packed registry in Julia 1.7+.
                file = joinpath(reg_dir, "$(name).toml")
            end

            if isfile(file)
                content =TOML.parsefile(file)

                spec = (
                    name = content["name"]::String,
                    uuid = UUID(content["uuid"]::String),
                    url = get(content, "repo", nothing)::Union{String,Nothing},
                    path = file
                )

                push!(registries, spec)
            end
        end
    end
    return registries
end

"""
    compute_tag_versions(current, version)

Given the `current` version from the package's Project.toml and the requested
release (`nothing`, `:major`, `:minor`, `:patch` or an explicit
`VersionNumber`), return the tuple `(version_to_be_tagged, next_dev_version)`.
"""
function compute_tag_versions(current::VersionNumber, version::Union{Symbol,VersionNumber,Nothing})
    version_to_be_tagged = if version===nothing
        current.prerelease==("DEV",) || error("Version in Project.toml must have format of x.y.z-DEV.")
        VersionNumber(current.major, current.minor, current.patch)
    elseif version isa VersionNumber
        version
    elseif version==:major && current.prerelease==("DEV",) && current.minor==0 && current.patch==0
        VersionNumber(current.major, 0, 0)
    elseif version==:major
        VersionNumber(current.major+1, 0, 0)
    elseif version==:minor && current.prerelease==("DEV",) && current.patch==0
        VersionNumber(current.major, current.minor, 0)
    elseif version==:minor
        VersionNumber(current.major, current.minor+1, 0)
    elseif version==:patch && current.prerelease==("DEV",)
        VersionNumber(current.major, current.minor, current.patch)
    elseif version==:patch
        VersionNumber(current.major, current.minor, current.patch+1)
    else
        error("Invalid argument for version, must be nothing, a VersionNumber, :major, :minor or :patch.")
    end

    next_version = VersionNumber(version_to_be_tagged.major, version_to_be_tagged.minor, version_to_be_tagged.patch+1, ("DEV",))

    return version_to_be_tagged, next_version
end

"""
    is_fork_of(gh_repo, gh_parent_repo)

Whether `gh_repo` is a fork of `gh_parent_repo`.
"""
function is_fork_of(gh_repo, gh_parent_repo)
    gh_repo===nothing && return false
    gh_repo.fork===true || return false

    for ancestor in (gh_repo.parent, gh_repo.source)
        ancestor===nothing && continue
        ancestor.full_name==gh_parent_repo.full_name && return true
    end

    return false
end

"""
    resolve_registry_push_target(gh_registry_repo, github_username, auth)

Work out where the registration branch for `gh_registry_repo` should be pushed.

Someone who can push to the registry itself (its owner, a collaborator, a member
of the owning organisation) does not have, and cannot make, a fork of it, so the
branch goes straight to the registry. Everyone else pushes to their own fork and
opens a cross-repository pull request from it.
"""
function resolve_registry_push_target(gh_registry_repo, github_username, auth)
    permissions = gh_registry_repo.permissions
    if permissions!==nothing && get(permissions, "push", false)===true
        return (
            owner_repo_name = string(gh_registry_repo.full_name),
            https_url = string(gh_registry_repo.html_url),
            is_fork = false
        )
    end

    # A fork keeps the name of the repository it was made from, so look it up
    # directly rather than paging through every fork of the registry.
    gh_fork = try
        GitHub.repo("$github_username/$(gh_registry_repo.name)", auth=auth)
    catch
        nothing
    end

    if !is_fork_of(gh_fork, gh_registry_repo)
        # A fork can be renamed though, and then there is no way around asking
        # for the whole list.
        gh_forks = GitHub.forks(gh_registry_repo, auth=auth)
        fork_index = findfirst(i->i.owner.login==github_username, gh_forks[1])
        fork_index===nothing && error("You need either push access to the registry $(gh_registry_repo.full_name) or a fork of it in the GitHub account $github_username.")
        gh_fork = gh_forks[1][fork_index]
    end

    return (
        owner_repo_name = string(gh_fork.full_name),
        https_url = string(gh_fork.html_url),
        is_fork = true
    )
end

function tag_internal(
        package_name::AbstractString,
        pkg_uuid, pkg_path::AbstractString,
        version::Union{Symbol,VersionNumber,Nothing}=nothing;
        registry::Union{AbstractString,Nothing}=nothing,
        release_notes::Union{AbstractString,Nothing}=nothing,
        credentials::Union{AbstractString, Nothing}=nothing,
        github_username::Union{AbstractString, Nothing} = nothing)

    general_reg_url = "https://github.com/JuliaRegistries/General"

    if github_username===nothing
        github_username = LibGit2.getconfig("github.user", "")
        github_username == "" && error("You need to configure the github.user setting.")
    end

    isdir(pkg_path) || error("Path for package does not exist on disc.")

    all_registries = our_collect_registries()

    private_reg_url, private_reg_uuid = if registry===nothing
        registries_that_contain_the_package = []
        for reg_spec in all_registries
            reg_data = TOML.parsefile(reg_spec.path)

            if haskey(reg_data["packages"], string(pkg_uuid))
                push!(registries_that_contain_the_package, reg_spec)
            end
        end

        if length(registries_that_contain_the_package)==0
            (nothing, nothing)
        elseif length(registries_that_contain_the_package)>1
            error("Package is registered in more than one registry, please specify in which you want to register the tag.")
        else
            (registries_that_contain_the_package[1].url, registries_that_contain_the_package[1].uuid)
        end
    else
        relevant_registry = findfirst(i->i.name==registry, all_registries)

        relevant_registry===nothing && error("The registry $registry does not exist.")

        (all_registries[relevant_registry].url, all_registries[relevant_registry].uuid)
    end

    if private_reg_uuid == UUID("23338594-aafe-5451-b93e-139f81909106")
        private_reg_url = nothing
        private_reg_uuid = nothing
    end

    if credentials===nothing        
        creds = LibGit2.GitCredential(GitConfig(), "https://github.com")

        creds.password===nothing && error("Did not find credentials for github.com in the git credential manager.")

        credentials = read(creds.password, String)
        Base.shred!(creds.password)
    end

    myauth = GitHub.authenticate(credentials)

    # A registration in General goes through Registrator, which needs neither the
    # registry repository nor a fork of it. Resolving them anyway meant paging
    # through every single fork of JuliaRegistries/General on every tag.
    gh_registry_repo, registry_push_target = if private_reg_url===nothing
        (nothing, nothing)
    else
        registry_repo_on_github = GitHub.repo(get_repo_onwer_from_url(private_reg_url), auth=myauth)

        # Resolved here, before the release branch is created, so that missing
        # access fails before anything has been committed or pushed.
        (registry_repo_on_github, resolve_registry_push_target(registry_repo_on_github, github_username, myauth))
    end

    pkg_repo = GitRepo(pkg_path)

    try

        LibGit2.isdirty(pkg_repo) && error("The repo for the package cannot be dirty.")

        pkg_remote = LibGit2.lookup_remote(pkg_repo, "origin")

        pkg_remote===nothing && error("The package must have a remote called origin.")

        pkg_url = LibGit2.url(pkg_remote)

        # Parse the remote URL up front: an unsupported one must fail before the
        # release branch is created, not half-way through the release.
        pkg_owner_repo_name = get_repo_onwer_from_url(pkg_url)

        pkg_project_toml_path = isfile(joinpath(pkg_path, "JuliaProject.toml")) ? joinpath(pkg_path, "JuliaProject.toml") : isfile(joinpath(pkg_path, "Project.toml")) ? joinpath(pkg_path, "Project.toml") : error("Couldn't find Project.toml.")

        pkg_toml_content = TOML.parsefile(pkg_project_toml_path)

        haskey(pkg_toml_content, "version") || error("Project.toml must have a version field.")

        current_version_in_pkg = VersionNumber(pkg_toml_content["version"])

        version_to_be_tagged, next_version = compute_tag_versions(current_version_in_pkg, version)

        # TODO Check whether that version already exists, and if so, error.

        name_of_release_branch = "release-$version_to_be_tagged"

        LibGit2.lookup_branch(pkg_repo, name_of_release_branch)===nothing || error("A branch named $name_of_release_branch already exists in the package.")

        name_of_old_branch_in_pkg = LibGit2.headname(pkg_repo)

        try
            LibGit2.branch!(pkg_repo, name_of_release_branch, force=true)

            # Now update the version field in the Project.toml

            pkg_toml_content["version"] = version_to_be_tagged

            open(pkg_project_toml_path, "w") do f
                TOML.print(TOML_print_conversion, f, pkg_toml_content)
            end

            # RegistryTools 2 takes its own Project type (or a path, but the file is
            # rewritten to the next dev version before registration happens).
            project_as_it_should_be_tagged = RegistryTools.Project(pkg_project_toml_path)

            LibGit2.add!(pkg_repo, splitdir(pkg_project_toml_path)[2])
            hash_of_commit_to_be_tagged = LibGit2.commit(pkg_repo, "Set version to v$version_to_be_tagged")

            tree_hash_of_commit_to_be_tagged = LibGit2.GitHash(LibGit2.peel(LibGit2.GitTree, LibGit2.GitCommit(pkg_repo, hash_of_commit_to_be_tagged)))

            # Now update the version field in the Project.toml

            pkg_toml_content = TOML.parsefile(pkg_project_toml_path)

            pkg_toml_content["version"] = next_version

            open(pkg_project_toml_path, "w") do f
                TOML.print(TOML_print_conversion, f, pkg_toml_content)
            end

            LibGit2.add!(pkg_repo, splitdir(pkg_project_toml_path)[2])
            LibGit2.commit(pkg_repo, "Set version to v$next_version")

            # git's output must not end up on stdout: when PkgDev runs embedded in a
            # host whose stdout is a protocol stream (e.g. an MCP server), that would
            # corrupt the stream.
            run(pipeline(Cmd(`git push origin refs/heads/$name_of_release_branch`, dir=pkg_path); stdout=stderr))

            LibGit2.branch!(pkg_repo, name_of_old_branch_in_pkg)

            LibGit2.delete_branch(LibGit2.lookup_branch(pkg_repo, name_of_release_branch))

            gh_pkg_repo = GitHub.repo(pkg_owner_repo_name, auth=myauth)

            GitHub.create_pull_request(gh_pkg_repo, auth=myauth, params=Dict(:title=>"New version: v$version_to_be_tagged", :head=>name_of_release_branch, :base=>name_of_old_branch_in_pkg, :body=>""))

            if private_reg_url===nothing
                body = "@JuliaRegistrator register()"

                if release_notes !== nothing
                    body *= "\n\nRelease notes:\n\n $release_notes\n"
                end

                GitHub.create_comment(gh_pkg_repo, string(hash_of_commit_to_be_tagged), :commit, params = Dict("body"=>body), auth=myauth)
            else
                mktempdir() do tmp_path
                    # The default RegistryTools cache is the relative path
                    # "registries", so pass one rooted in the temporary directory
                    # instead of cd-ing the whole process into it.
                    registry_cache = RegistryTools.RegistryCache(joinpath(tmp_path, "registries"))
                    folder_for_registry = joinpath(tmp_path, "registries", string(private_reg_uuid))

                    regbranch = RegistryTools.register(https_url_from_git_url(pkg_url), project_as_it_should_be_tagged, string(tree_hash_of_commit_to_be_tagged); registry=private_reg_url, registry_deps=[general_reg_url], push=false, cache=registry_cache)

                    @info regbranch.metadata

                    # Push over the same transport the package itself uses:
                    # someone working over ssh has no https credentials.
                    registry_push_url = if uses_ssh_transport(pkg_url)
                        ssh_url_from_repo(parse_git_url(registry_push_target.https_url).host, registry_push_target.owner_repo_name)
                    else
                        registry_push_target.https_url
                    end

                    registry_repo = GitRepo(folder_for_registry)
                    try
                        run(pipeline(Cmd(`git push $registry_push_url refs/heads/$(regbranch.branch)`, dir=folder_for_registry); stdout=stderr))
                    finally
                        close(registry_repo)
                    end

                    body = ""
                    if release_notes !== nothing
                        # Prepend every line with '> ' to quote it (this format is expected by TagBot).
                        notes = join(map(line -> "> $line", split(release_notes, "\n")), "\n")
                        body *= """

                            Release notes:
                            <!-- BEGIN RELEASE NOTES -->
                            $notes
                            <!-- END RELEASE NOTES -->
                            """
                    end

                    # A branch pushed to a fork is referred to as owner:branch,
                    # one pushed to the registry itself just by its name.
                    pr_head = registry_push_target.is_fork ? "$github_username:$(regbranch.branch)" : regbranch.branch

                    GitHub.create_pull_request(gh_registry_repo, auth=myauth, params=Dict(:title=>"New version: $package_name v$version_to_be_tagged", :head=>pr_head, :base=>something(gh_registry_repo.default_branch, "master"), :body=>strip(body)))
                end
            end
        catch
            # Best-effort local rollback: return to the branch we started on
            # (discarding anything the release flow left in the working tree) and
            # delete the local release branch, so that a retry does not fail with
            # "A branch named ... already exists". Anything that was already created
            # remotely is left alone.
            try
                if LibGit2.headname(pkg_repo) != name_of_old_branch_in_pkg
                    old_branch_ref = LibGit2.lookup_branch(pkg_repo, name_of_old_branch_in_pkg)
                    if old_branch_ref !== nothing
                        old_commit = LibGit2.peel(LibGit2.GitCommit, old_branch_ref)
                        LibGit2.checkout!(pkg_repo, string(LibGit2.GitHash(old_commit)))
                        LibGit2.branch!(pkg_repo, name_of_old_branch_in_pkg)
                    end
                end
            catch rollback_error
                @warn "Could not switch back to the original branch $name_of_old_branch_in_pkg." exception=rollback_error
            end
            try
                release_branch_ref = LibGit2.lookup_branch(pkg_repo, name_of_release_branch)
                release_branch_ref===nothing || LibGit2.delete_branch(release_branch_ref)
            catch rollback_error
                @warn "Could not delete the local branch $name_of_release_branch." exception=rollback_error
            end
            @warn "Tagging failed part-way through. The local repository has been restored, but anything that was already created remotely — the pushed $name_of_release_branch branch, a pull request or a registration request — is still there and should be inspected before retrying."
            rethrow()
        end
    finally
        close(pkg_repo)
    end

    return nothing
end
