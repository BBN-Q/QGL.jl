# https://discourse.julialang.org/t/yaml-jl-custom-tag-constructor-example-include/3900

module yaml

export load_file_relative

using YAML

const _constructors = Dict{String, Function}()

"""Loads YAML files relative to the current directory"""
function load_file_relative(filename::AbstractString;
    constructors::Dict{String, Function}=_constructors
)
    filename = abspath(filename)
    cd(dirname(filename)) do
        YAML.load_file(filename, constructors)
    end
end

"""Processes an !include constructor"""
function construct_include(constructor::YAML.Constructor, node::YAML.ScalarNode)
    filename = node.value
    if !isfile(filename)
        throw(YAML.ConstructorError(nothing, nothing, "file $(abspath(filename)) does not exist", node.start_mark))
    end
    if !(last(splitext(filename)) in (".yaml", ".yml", ".json"))
        return readstring(filename)
    end
    # pass forward custom constructors
    constructors = Dict{String, Function}(
        tag => f for (tag, f) in constructor.yaml_constructors
        if tag !== nothing && ismatch(r"^!\w+$", tag)
    )
    load_file_relative(filename; constructors=constructors)
end
construct_include(::YAML.Constructor, node::YAML.Node) = throw(
    YAML.ConstructorError(nothing, nothing, "expected a scalar node, but found $(typeof(node))", node.start_mark)
)
_constructors["!include"] = construct_include

end
