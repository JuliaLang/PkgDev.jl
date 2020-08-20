function format(package_name, formatopts::DocumentFormat.FormatOptions = DocumentFormat.FormatOptions())
    ctx = Pkg.Types.Context()
    haskey(ctx.env.project.deps, package_name) || error("Unknown package $package_name.")
    pkg_uuid = ctx.env.project.deps[package_name]
    pkg_path = ctx.env.manifest[pkg_uuid].path
    pkg_path===nothing && error("Package must be deved to be formatted.")

    DocumentFormat.format(Path(pkg_path), formatopts)
end
