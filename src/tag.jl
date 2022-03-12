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

    registry_github_owner_repo_name = private_reg_url===nothing ? "JuliaRegistries/General" : get_repo_onwer_from_url(private_reg_url)

    gh_registry_repo = GitHub.repo(registry_github_owner_repo_name, auth=myauth)
    gh_forks = GitHub.forks(gh_registry_repo)
    fork_index = findfirst(i->i.owner.login==github_username, gh_forks[1])
    fork_index===nothing && error("You need to have a fork of the registry in your github account.")
    registry_fork_url = string(gh_forks[1][fork_index].html_url)

    pkg_repo = GitRepo(pkg_path)

    try

        LibGit2.isdirty(pkg_repo) && error("The repo for the package cannot be dirty.")

        pkg_remote = LibGit2.lookup_remote(pkg_repo, "origin")

        pkg_remote===nothing && error("The package must have a remote called origin.")

        pkg_url = LibGit2.url(pkg_remote)

        pkg_project_toml_path = isfile(joinpath(pkg_path, "JuliaProject.toml")) ? joinpath(pkg_path, "JuliaProject.toml") : isfile(joinpath(pkg_path, "Project.toml")) ? joinpath(pkg_path, "Project.toml") : error("Couldn't find Project.toml.")

        pkg_toml_content = TOML.parsefile(pkg_project_toml_path)

        haskey(pkg_toml_content, "version") || error("Project.toml must have a version field.")

        current_version_in_pkg = VersionNumber(pkg_toml_content["version"])

        version_to_be_tagged = if version===nothing
            current_version_in_pkg.prerelease!=("DEV",) && current_version_in_pkg.build!=() && error("Version in Project.toml must have format of x.y.z-DEV.")
            VersionNumber(current_version_in_pkg.major, current_version_in_pkg.minor, current_version_in_pkg.patch)
        elseif version isa VersionNumber
            version
        elseif version==:major
            VersionNumber(current_version_in_pkg.major+1, 0, 0)
        elseif version==:minor
            VersionNumber(current_version_in_pkg.major, current_version_in_pkg.minor+1, 0)
        elseif version==:patch && current_version_in_pkg.prerelease==("DEV",)
            VersionNumber(current_version_in_pkg.major, current_version_in_pkg.minor, current_version_in_pkg.patch)
        elseif version==:patch
            VersionNumber(current_version_in_pkg.major, current_version_in_pkg.minor, current_version_in_pkg.patch+1)
        else
            error("Invalid argument for version, must be nothing, a VersionNumber, :major, :minor or :patch.")
        end

        next_version = VersionNumber(version_to_be_tagged.major, version_to_be_tagged.minor, version_to_be_tagged.patch+1, ("DEV",))

        # TODO Check whether that version already exists, and if so, error.

        name_of_release_branch = "release-$version_to_be_tagged"

        LibGit2.lookup_branch(pkg_repo, name_of_release_branch)===nothing || error("A branch named $name_of_release_branch already exists in the package.")

        name_of_old_branch_in_pkg = LibGit2.headname(pkg_repo)

        LibGit2.branch!(pkg_repo, name_of_release_branch, force=true)

        # Now update the version field in the Project.toml

        pkg_toml_content["version"] = version_to_be_tagged

        open(pkg_project_toml_path, "w") do f
            TOML.print(TOML_print_conversion, f, pkg_toml_content)
        end

        project_as_it_should_be_tagged = Pkg.Types.read_project(pkg_project_toml_path)

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

        run(Cmd(`git push origin refs/heads/$name_of_release_branch`, dir=pkg_path))

        LibGit2.branch!(pkg_repo, name_of_old_branch_in_pkg)

        LibGit2.delete_branch(LibGit2.lookup_branch(pkg_repo, name_of_release_branch))

        pkg_owner_repo_name = get_repo_onwer_from_url(pkg_url)

        gh_pkg_repo = GitHub.repo(pkg_owner_repo_name, auth=myauth)

        GitHub.create_pull_request(gh_pkg_repo, auth=myauth, params=Dict(:title=>"New version: v$version_to_be_tagged", :head=>name_of_release_branch, :base=>name_of_old_branch_in_pkg, :body=>""))

        if private_reg_url===nothing
            GitHub.create_comment(gh_pkg_repo, string(hash_of_commit_to_be_tagged), :commit, params = Dict("body"=>"@JuliaRegistrator register()"), auth=myauth)
        else
            mktempdir() do tmp_path
                cd(tmp_path) do
                    folder_for_registry = nothing
                    regbranch = if private_reg_url===nothing
                        folder_for_registry = joinpath(tmp_path, "registries", "23338594-aafe-5451-b93e-139f81909106")
                        RegistryTools.register(pkg_url, project_as_it_should_be_tagged, string(tree_hash_of_commit_to_be_tagged); registry=general_reg_url, push=false)
                    else
                        folder_for_registry = joinpath(tmp_path, "registries", string(private_reg_uuid))
                        RegistryTools.register(pkg_url, project_as_it_should_be_tagged, string(tree_hash_of_commit_to_be_tagged); registry=private_reg_url, registry_deps=[general_reg_url], push=false)
                    end

                    @info regbranch.metadata

                    registry_repo = GitRepo(folder_for_registry)
                    try
                        run(Cmd(`git push $registry_fork_url refs/heads/$(regbranch.branch)`, dir=folder_for_registry))
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

                    GitHub.create_pull_request(gh_registry_repo, auth=myauth, params=Dict(:title=>"New version: $package_name v$version_to_be_tagged", :head=>"$github_username:$(regbranch.branch)", :base=>"master", :body=>strip(body)))
                end
            end
        end
    finally
        close(pkg_repo)
    end

    return nothing
end
