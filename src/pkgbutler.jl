function enable_pkgbutler(package_name::AbstractString)
    ctx = Pkg.Types.Context()
    haskey(ctx.env.project.deps, package_name) || error("Unkonwn package $package_name.")
    pkg_uuid = ctx.env.project.deps[package_name]
    pkg_path = ctx.env.manifest[pkg_uuid].path
    pkg_path===nothing && error("Package must be deved to enable the Julia Package Butler.")

    PkgButlerEngine.update_pkg(pkg_path)
end

function configure_deploykey()
    pub_deploykey, private_deploykey = mktempdir() do f
        p = joinpath(f, "deploykey")
        run(`ssh-keygen -q -t rsa -f $p -N ''`)

        pub_deploykey = read("$p.pub", String)
        private_deploykey = read(p, String)

        rm(p, force=true)
        rm("$p.pub", force=true)

        return pub_deploykey, private_deploykey
    end
end