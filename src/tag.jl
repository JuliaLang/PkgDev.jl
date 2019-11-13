function tag(package_name::AbstractString, version::Union{Symbol,VersionNumber,Nothing}=nothing; registry::Union{AbstractString,Nothing}=nothing)
    general_reg_url = "https://github.com/JuliaRegistries/General"

    github_username = LibGit2.getconfig("github.user", "")

    github_username == "" && error("You need to configure the github.user setting.")

    ctx = Pkg.Types.Context()
    haskey(ctx.env.project.deps, package_name) || error("Unkonwn package $package_name.")
    pkg_uuid = ctx.env.project.deps[package_name]
    pkg_path = ctx.env.manifest[pkg_uuid].path
    pkg_path===nothing && error("Package must be deved to be tagged.")

    all_registries = Pkg.Types.collect_registries()

    private_reg_url, private_reg_uuid = if registry===nothing
        registries_that_contain_the_package = []
        for reg_spec in all_registries
            reg_data = Pkg.Types.read_registry(joinpath(reg_spec.path, "Registry.toml"))

            if haskey(reg_data["packages"], string(pkg_uuid))
                push!(registries_that_contain_the_package, reg_spec)
            end
        end

        if length(registries_that_contain_the_package)==0
            (nothing, nothing)
        elseif length(registries_that_contain_the_package)>1
            error("Package is registered in more than on registry, please specify in which you want to register the tag.")
        else
            (registries_that_contain_the_package[1].url, registries_that_contain_the_package[1].uuid)
        end
    else
        relevant_registry = findfirst(i->i.name==registry, all_registries)

        relevant_registry===nothing && error("The registry $registry does not exist.")

        (all_registries[relevant_registry].url, all_registries[relevant_registry].uuid)
    end

    creds = LibGit2.GitCredential(GitConfig(), "https://github.com")

    # TODO Check for creds===nothing if there are no credentials stored
    myauth = GitHub.authenticate(read(creds.password, String))
    Base.shred!(creds.password)

    registry_github_owner_repo_name = private_reg_url===nothing ? "JuliaRegistries/General" : splitext(URI(private_reg_url).path)[1][2:end]

    gh_registry_repo = GitHub.repo(registry_github_owner_repo_name)
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

        pkg_toml_content = Pkg.TOML.parsefile(pkg_project_toml_path)

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
            Pkg.TOML.print(f, pkg_toml_content)
        end

        project_as_it_should_be_tagged = Pkg.Types.read_project(pkg_project_toml_path)

        LibGit2.add!(pkg_repo, splitdir(pkg_project_toml_path)[2])
        hash_of_commit_to_be_tagged = LibGit2.commit(pkg_repo, "Set version to v$version_to_be_tagged")

        tree_hash_of_commit_to_be_tagged = LibGit2.GitHash(LibGit2.peel(LibGit2.GitTree, LibGit2.GitCommit(pkg_repo, hash_of_commit_to_be_tagged)))

        # Now update the version field in the Project.toml

        pkg_toml_content = Pkg.TOML.parsefile(pkg_project_toml_path)

        pkg_toml_content["version"] = next_version

        open(pkg_project_toml_path, "w") do f
            Pkg.TOML.print(f, pkg_toml_content)
        end

        LibGit2.add!(pkg_repo, splitdir(pkg_project_toml_path)[2])
        LibGit2.commit(pkg_repo, "Set version to v$next_version")

        run(Cmd(`git push origin refs/heads/$name_of_release_branch`, dir=pkg_path))

        LibGit2.branch!(pkg_repo, name_of_old_branch_in_pkg)

        LibGit2.delete_branch(LibGit2.lookup_branch(pkg_repo, name_of_release_branch))

        pkg_owner_repo_name = splitext(URI(pkg_url).path)[1][2:end]

        gh_pkg_repo = GitHub.repo(pkg_owner_repo_name, auth=myauth)

        GitHub.create_pull_request(gh_pkg_repo, auth=myauth, params=Dict(:title=>"New version: v$version_to_be_tagged", :head=>name_of_release_branch, :base=>name_of_old_branch_in_pkg, :body=>""))

        mktempdir() do tmp_path
            cd(tmp_path) do
                folder_for_registry = nothing
                regbranch = if private_reg_url===nothing
                    folder_for_registry = joinpath(tmp_path, "registries", "23338594-aafe-5451-b93e-139f81909106")
                    RegistryTools.RegEdit.register(pkg_url, project_as_it_should_be_tagged, string(tree_hash_of_commit_to_be_tagged); registry=general_reg_url, push=false)
                else
                    folder_for_registry = joinpath(tmp_path, "registries", string(private_reg_uuid))
                    RegistryTools.RegEdit.register(pkg_url, project_as_it_should_be_tagged, string(tree_hash_of_commit_to_be_tagged); registry=private_reg_url, registry_deps=[general_reg_url], push=false)
                end

                registry_repo = GitRepo(folder_for_registry)
                try
                    run(Cmd(`git push $registry_fork_url refs/heads/$(regbranch.branch)`, dir=folder_for_registry))
                finally
                    close(registry_repo)
                end

                GitHub.create_pull_request(gh_registry_repo, auth=myauth, params=Dict(:title=>"New version: $package_name v$version_to_be_tagged", :head=>"$github_username:$(regbranch.branch)", :base=>"master", :body=>""))
            end
        end
    finally
        close(pkg_repo)
    end
end