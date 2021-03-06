"Module that is responsible for all IO operations, like loading terrain data
from file."
module ProjectIO

using ..Adaptation
using ..Utils
using ..Visualization

export
    load_data,
    load_heightmap,
    saveGML,
    export_obj,
    export_simulation

using LightGraphs
using MetaGraphs
using Printf
using GLMakie

import Images

"Load terrain data (in bytes) as `TerrainMap`"
function load_data(filename, dims, type=Float64)::TerrainMap
    bytes_data =  open(f->read(f), filename)
    nicer_data = reinterpret(Int16, bytes_data)
    dim = Int(sqrt(size(nicer_data)[1]))
    matrix = reshape(nicer_data, (dim, dim))
    as_type =  map(x -> type(x), matrix)
    scale = maximum(as_type) - minimum(as_type)
    offset = minimum(as_type)
    # normalized is in range 1.0 to 2.0
    normalized = map(x -> (x - offset) / scale, as_type + 1.0)
    return TerrainMap(reversed, dims[1], dims[2], scale)
end

"""
    load_heightmap(filename, dims, scale=1.0, offset=0.0, type=Float64)

Load heighmap as `TerrainMap`.

# Arguments
- `filename::String`: path to file containing heightmap.
- `dims::Array{<:Real, 1}`: size of terrain as 2-element array [x, y]. **Note: **
 it can't be too small (many times smaller than heighmap size) as it may lead to
 problems with float representation (`==`).
- `scale::Real=1.0`: Pixels in heightmap are in range [0, 1]. To calculate real
 height it is then multiplied by `scale`.
- `offset::Real=0,0`: it is added to previous result in order to calculate real
 height.
- `type::Type=Float64`: How pixels will be represented in returned struct.

See also [`TerrainMap`](@ref)
"""
function load_heightmap(filename, dims, scale=1.0, offset=0.0, type=Float64)::TerrainMap
    img = Images.load(filename)
    grayscale = Images.Gray.(img)
    f(x) = type(Images.gray(x) + 1)
    # mapped is in range 1.0 to 2.0
    mapped = map(f, grayscale)
    println(maximum(mapped), " ", minimum(mapped))
    reversed = reverse(mapped, dims=1)
    return TerrainMap(reversed, dims[1], dims[2], scale, offset)
end

"Save graph `g` as GML file."
function saveGML(g, filename)
    open(filename, "w") do io
        write(io, "graph [\n")
        write(io, "\tdirected 0\n")

        for v in 1:nv(g)
            write(io, "\tnode [\n")

            write(io, @sprintf("\t\tid %d\n", v))
            for pair in props(g, v)
                write(io, @sprintf("\t\t%s %s\n", string(pair[1]), string(pair[2])))
            end

            write(io, "\t]\n")
        end

        for e in edges(g)
            write(io, "\tedge [\n")

            write(io, @sprintf("\t\tsource %d\n", src(e)))
            write(io, @sprintf("\t\ttarget %d\n", dst(e)))
            for pair in props(g, e)
                write(io, @sprintf("\t\t%s %s\n", string(pair[1]), string(pair[2])))
            end

            write(io, "\t]\n")
        end

        write(io, "]\n")
    end
end

"Export graph as OBJ. If flag `include_fun` is set also export function that mesh
approximates (requires `value` property set)."
function export_obj(g, filename, include_fun=false)
    open(filename, "w") do io
        v_id = 1
        t_map = Dict()
        fun_map = Dict()
        for v in normal_vertices(g)
            write(io, @sprintf("v %f %f %f\n", x(g, v), y(g, v), z(g, v)))
            t_map[v] = v_id
            v_id += 1
        end

        if include_fun
            for v in normal_vertices(g)
                write(io, @sprintf("v %f %f %f\n", x(g, v), y(g, v), z(g, v) + get_prop(g, v, :value)))
                fun_map[v] = v_id
                v_id += 1
            end
        end

        for i in interiors(g)
            v1, v2, v3 = interior_vertices(g, i)
            write(io, @sprintf("f %d %d %d\n", t_map[v1], t_map[v2], t_map[v3]))
            if include_fun
                write(io, @sprintf("f %d %d %d\n", fun_map[v1], fun_map[v2], fun_map[v3]))
            end
        end
    end
end

"""
    export_simulation(g, values; filename="sim.mp4", fps=24)

Export simulation as video. Values is matrix returned from [`simulate`](@ref).
"""
function export_simulation(g, values; filename="sim.mp4", fps=24,
    transparent_fun=false, shading_fun=true, show_axis=false)
    set_values!(g, values[1,:])
    scene = draw_makie(g; include_fun=false, show_axis=show_axis)
    vertices, faces = function_mesh(g)

    # Makie can't draw empty meshes - so if it should I just draw single trinagle
    if isempty(faces)
        faces = [1 2 3]
    end
    current_mesh = mesh!(vertices, faces, color=:lightblue, shading=shading_fun, transparency=transparent_fun)

    record(scene, filename, 1:size(values)[1]; framerate=fps) do i
        set_values!(g, values[i,:])
        vertices, faces = function_mesh(g)
        current_mesh[1] = vertices

        # Same here
        if !isempty(faces)
            current_mesh[2] = faces
        else
            current_mesh[2] = [1 2 3]
        end
    end
end

end
