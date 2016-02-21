const LICENSES = Dict(
    "MIT" => "MIT \"Expat\" License",
    "BSD" => "Simplified \"2-clause\" BSD License",
    "ASL" => "Apache License, Version 2.0",
    "MPL" => "Mozilla Public License, Version 2.0"
)


"Read license text from specified file and location"
function readlicense(lic::AbstractString,
                     dir::AbstractString=normpath(dirname(@__FILE__), "..", "res", "licenses"))
    return open(readstring, joinpath(dir, lic))
end

"""
    license([name])

Shows available licenses if no parameters specified. If a license name is specified as a parameter then the function shows the license text.
"""
function license(lic::AbstractString="")
    if isempty(lic)
        lics =""
        for k in LICENSES |> keys |> collect |> sort
            lics *= " $k | $(LICENSES[k])\n"
        end
        maxdesclen = maximum(map(length,values(LICENSES)))
        lics = "Label| Full name\n-----|$(repeat("-", maxdesclen+2))\n$lics"
        println(lics)
        # Base.Markdown.term(STDOUT, lics)
    else
        try
            println(readlicense(lic))
        catch
            print_with_color(:red, "License $lic is not available.")
        end
    end
end
